# B4-0A -- RUNSHEET   (v5 -- post-auditoria 5)

Rol PG dedicado + schema dedicado + gateway SQL de admision por tickets para el
Motor de Precios v2. **Solo TEST.** Nada de esto se ejecuta en OPS.

**Ejecuta Franco. Claude no toca Supabase, n8n, Vercel ni git.**

---

## 0. Que instala esto

| | |
|---|---|
| Schema | `precios_api` -- owner postgres, cerrado a PUBLIC, USAGE (no CREATE) para el rol |
| Rol | `vita_precios_api` -- NOLOGIN al crearse, sin privilegios de tabla ni de secuencia |
| Tablas | 4 (todas en `precios_api`) |
| Funciones | 19 en `precios_api`: **5 SECURITY DEFINER** (entrypoints) + **14 SECURITY INVOKER** |
| Jobs `pg_cron` | 4 purgas |
| Secuencias | **0** |
| Hardening | `REVOKE` owner-only sobre las 13 `precios_*` de B3 (**solo eso**) |
| Superficie del rol | **5 `EXECUTE`** en `precios_api` (4 al retirar el probe) |

**Instalacion FRESH-ONLY.** Si hay cualquier residuo de B4 (schema, rol, tabla,
funcion o job), el script **aborta** y pide correr el rollback.

---

## 1. Orden de ejecucion

| # | Que | Donde | Cuando parar |
|---|---|---|---|
| 1 | `B4_0A_v5_ROL_TABLAS_FUNCIONES.sql` | SQL Editor de TEST | si aborta -> leer el motivo, correr rollback |
| 2 | `ALTER ROLE ... LOGIN PASSWORD` (§3) | SQL Editor de TEST | -- |
| 3 | `B4_0A_v5_VERIFY.sql` | SQL Editor de TEST | **si hay 1 solo FAIL -> parar** |
| 4 | Guardar la connection string (§6) | gestor de secretos | -- |

> Supabase SQL Editor: correr con **nada seleccionado** (L-8A-01), o ejecuta solo
> el texto marcado.

---

## 2. Los cinco gates de entrada (paso 1)

Los cinco corren **antes** de crear un solo objeto, en la misma transaccion.

| Gate | Aborta si... |
|---|---|
| **Ambiente** | `configuracion_general('ambiente') <> 'test'` |
| **Anti-residuos** | existe el schema, el rol, cualquier objeto/funcion `api_precios_*`, o alguno de los 4 jobs |
| **Preflight `pg_cron`** | no existe `cron.schedule(text,text,text)` o `cron.unschedule(text)` **con esa firma exacta** (`to_regprocedure`), o falta `cron.job` |
| **Preflight upstream** | cualquiera de los **tres fingerprints** no coincide (ver §4) |
| **CREATE en public** | `has_schema_privilege('vita_precios_api','public','CREATE')` es `true` |
| **CREATE en la base** | `has_database_privilege('vita_precios_api', current_database(), 'CREATE')` es `true` (podria crear schemas propios) |
| **ACL precommit** (§1.quater) | el rol puede **invocar** un `SECURITY DEFINER` ajeno, o tiene **algun** privilegio de tabla o de secuencia |

**Por que la firma exacta de cron:** `pg_cron` trae sobrecargas (`unschedule(bigint)`
ademas de `unschedule(text)`). Encontrar "cualquier `proname='schedule'`" no prueba
que exista **la** firma que B4-0A invoca.

### El gate ACL precommit puede abortar la instalacion. Es a proposito.

**§1.quater corre DESPUES de crear el rol y ANTES de crear un solo objeto de B4.**
Aborta toda la transaccion si el rol ya nace con:

- **un `SECURITY DEFINER` ajeno REALMENTE INVOCABLE** (superficie efectiva: `USAGE`
  de schema **+** `EXECUTE` de funcion) -> eso es **escalada de privilegios**;
- **cualquier** privilegio de tabla;
- **cualquier** privilegio de secuencia.

> **Anticipacion honesta:** si TEST tiene funciones `SECURITY DEFINER` en `public`
> con `EXECUTE` a `PUBLIC` -- lo cual es **plausible** --, **este gate va a abortar
> la instalacion** y te va a listar las primeras 20 con su firma exacta. **Eso es lo
> que tiene que pasar.** No lo saltees: revisalas, revocalas de `PUBLIC`, y volve a
> correr. Instalar B4-0A con un SECDEF ajeno alcanzable le daria al rol un camino de
> escalada que ningun otro control tapa.

El REVOKE del motor B3 (§1.ter) se **adelanto** para que corra **antes** de este
gate: las 13 `precios_*` se cierran primero, y despues se mide la superficie. Si no,
el gate las contaria a ellas.

**Por que los dos checks de CREATE:** un `REVOKE` dirigido al rol **no arregla un
permiso heredado de `PUBLIC`** (medido). Por eso se **comprueba el efectivo**, no se
asume. Son dos superficies distintas:

- **CREATE sobre el schema `public`** -> podria plantar funciones o tablas ahi.
- **CREATE sobre la BASE** -> podria crear **schemas propios**, y dentro de un
  schema propio es **owner**: crea lo que quiera.

Si alguno diera `true`, el script aborta y dice como corregirlo.

---

## 3. Password del rol

`RandomNumberGenerator` (CSPRNG), **no** `Get-Random` (PRNG determinista, no apto
para credenciales). 32 bytes -> **64 caracteres hex** (evita URL-encoding en la
connection string: sin `+`, `/`, `=`).

```powershell
$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$pwd = -join ($bytes | ForEach-Object { $_.ToString('x2') })
$pwd
```

En el SQL Editor de TEST:

```sql
ALTER ROLE vita_precios_api LOGIN PASSWORD '<los 64 hex>';
```

> Esta linea **no va a git, ni a un artefacto, ni a un mensaje.** Password directo
> al gestor de secretos.

---

## 4. Preflight upstream -- por FINGERPRINT, no por conteo

Los conteos (13 funciones, 7 tablas, 32 tarifas, 8 temporadas continuas) se
conservan como **`[diag]`**: dicen *que* fallo, no alcanzan para probar que el
motor es el esperado. La prueba son los **tres fingerprints canonicos**:

| Fingerprint | Valor esperado | Algoritmo |
|---|---|---|
| **B2A estructural** | `da52a16c045689523a5f1f113f513a87` (124 lineas) | el de `B2A_VERIFY.sql` |
| **B2B datos** | `6d1653748d68ee9b62aa20aba5f3333d` (40 lineas) | el de `B2B_VERIFY.sql` |
| **B3 normalizado** | `098f2fe7916e11ffa78cff37622b9064` | `md5` de `prosrc` sin `\r` |

Los tres se comprueban en **el SQL principal**, en el **VERIFY** y en el **rollback**.

> **`SET LOCAL search_path = public, pg_catalog`.** El fingerprint B2A usa
> `conrelid::regclass::text`, cuyo texto **depende del `search_path`**: con `public`
> da `tarifas_motor`; sin `public` el cast **falla** con `UndefinedTable`. Los tres
> scripts lo fijan explicitamente para reproducir el hash que produjo `B2A_VERIFY`
> en el SQL Editor. **Medido.**

---

## 5. Privilegio minimo -- 5 SECURITY DEFINER, 14 SECURITY INVOKER

**DEFINER (5, los entrypoints):** `api_precios_admitir`, `api_precios_cotizar_exponer`,
`api_precios_congelar_exponer`, `api_precios_obtener_exponer`, `api_precios_probe_ambiente`.

**INVOKER (14):** los 3 core, los 7 helpers y las 4 purgas.

Por que funciona:
- llamados **desde un entrypoint**, su invocador efectivo ya es `postgres`;
- llamados por **pg_cron** (las purgas), el invocador es `postgres`;
- si una ACL se abriera por accidente, **no heredan privilegios elevados**.

**Medido en PostgreSQL real:**

| Escenario | Resultado |
|---|---|
| rol -> entrypoint(DEFINER) -> core(INVOKER) | corre como `postgres`. **Funciona.** |
| rol -> core(INVOKER) directo | `permission denied` (ACL owner-only) |
| **ACL abierta + INVOKER** | `permission denied` al tocar la tabla -> **NO escala** |
| **ACL abierta + DEFINER** | **leyo el dato privado** -> el riesgo es real |

El smoke `s_invoker_no_escala` prueba las cuatro situaciones y restaura el estado.

---

## 6. Connection string -- Supavisor en TRANSACTION mode

La Edge usa el **transaction pooler**, no session:

- **puerto 6543** (no 5432, que es session)
- **`prepare: false`** (transaction mode no soporta prepared statements)
- **usuario con project ref**: `vita_precios_api.<project-ref>`

**No inventar la cadena.** En el dashboard de Supabase, copiar la **Transaction
pooler connection string** y adaptar **unicamente** el usuario, conservando el
project ref y el host que ya trae:

```
# lo que da el dashboard (usuario postgres):
postgresql://postgres.<project-ref>:[PASSWORD]@aws-0-<region>.pooler.supabase.com:6543/postgres

# adaptado para el rol (mismo host, mismo puerto, mismo project-ref):
postgresql://vita_precios_api.<project-ref>:<64hex>@aws-0-<region>.pooler.supabase.com:6543/postgres
```

B4-0B prueba **esta misma cadena**.

---

## 7. Aislamiento -- que cierra cada capa, y que NO

| Capa | Que cierra | Que NO cierra |
|---|---|---|
| **Schema dedicado `precios_api`** | los entrypoints no viven en `public`; el rol tiene USAGE ahi y no necesita `public` | el USAGE sobre `public` que el rol **hereda de `PUBLIC`** |
| **`REVOKE` §9.bis (13 `precios_*`)** | el motor B3 queda owner-only: el rol **no puede** llamarlo directo y saltear cuota+nonce+ticket | funciones ajenas de `public` |
| **Gates de CREATE (§1.bis)** | el rol no puede crear nada: ni en `public`, ni schemas nuevos | -- |
| **`D03` -- cero SECDEF invocable** | ninguna funcion `SECURITY DEFINER` ajena es alcanzable -> **no hay escalada** | -- |

### Lo que B4-0A **NO** hace (a proposito)

**No aplica hardening global de ningun tipo.** En particular, **no** modifica los
default privileges del proyecto. Ese cambio es **global, persistente y con efectos
medidos fuera de B4** (funciones futuras de todo el proyecto; migraciones que
dependan del `EXECUTE` implicito; `anon` / `authenticated` / `authenticator`, que
**pierden acceso a toda funcion nueva expuesta por PostgREST** si dependian de
`PUBLIC`; `CREATE TYPE ... AS RANGE` para no-superusers; extensiones y scripts
futuros), y el rollback de B4-0A **no lo revierte**.

Un cambio de ese alcance no puede viajar dentro de un bloque cuyo rollback no lo
deshace. **Se trata en un frente de hardening independiente, todavia por disenar
y auditar. Desde aca no se aplica, no se verifica y no se revierte.**

**B4-0A no lo necesita.** La consecuencia de no tenerlo es que las funciones de
`public` con `EXECUTE` a `PUBLIC` -- actuales y futuras -- son invocables por el
rol. Eso **no queda oculto**: lo mide `D07` y lo lista la Salida 3 (ver §14).

---

## 8. Claim de seguridad -- lo que el VERIFY prueba, y lo que no

**No se afirma "cinco funciones y nada mas en toda la base".** El rol conserva
`USAGE` sobre `public` heredado de `PUBLIC`.

### Superficie **efectiva**, no nominal

`has_function_privilege()` **solo no alcanza**: una funcion con `EXECUTE` en un
schema sobre el que el rol **no tiene `USAGE`** es **inalcanzable**. Contarla como
superficie infla el riesgo y mezcla dos cosas distintas. La superficie **realmente
invocable** es la interseccion:

```sql
has_schema_privilege('vita_precios_api', n.oid, 'USAGE')
  AND has_function_privilege('vita_precios_api', p.oid, 'EXECUTE')
```

`D03` y el claim usan **esa** superficie. Las que tienen `EXECUTE` pero **no**
`USAGE` salen en una fila aparte de la Salida 3 (`sin USAGE (inalcanzable)`):
no cuentan hoy, pero si alguien concediera `USAGE` sobre ese schema, pasarian a contar.

### El claim exacto

| Afirmacion | Check |
|---|---|
| En `precios_api`: **exactamente 5** funciones **invocables** por el rol | `D01` + `D02` |
| **Cero `SECURITY DEFINER` invocable** fuera de la allowlist, en **cualquier** schema | **`D03`** -- el que impide escalada |
| **Cero `EXECUTE`** sobre el motor B3 | **`D04`** -- impide saltear cuota+nonce+ticket |
| **Cero privilegios de tabla y de secuencia** en toda la base | `D05` + `D06` |
| El rol **no puede crear nada**: ni en `public`, ni schemas nuevos | `A11` + `A13` |
| **Residual conocido:** via el `USAGE` heredado, el rol puede invocar funciones de `public` con `EXECUTE` a `PUBLIC` (actuales **y futuras**) | `D07` [info] + Salida 3 |

Cerrar el residual exige **hardening global**, que esta **fuera del alcance de
B4-0A** (ver §14). **B4-0A no lo tapa ni finge taparlo: lo declara y lo mide.**

El VERIFY imprime este claim como ultima salida.

---

## 9. Que defiende de verdad, y que no

### Threat model -- credencial PostgreSQL comprometida

**No se afirma que el atacante "solo puede ejecutar cinco funciones".** Eso seria
falso: el rol tiene una **conexion SQL real**, no un endpoint HTTP.

**Claim correcto:**

> Los permisos de **datos** y la **superficie de negocio** quedan limitados a los
> entrypoints B4. Una credencial PG comprometida conserva una **superficie SQL
> residual** y **capacidad de consumo de recursos**.

**Lo que el atacante SI conserva, con la credencial en la mano:**

| Superficie residual | Por que |
|---|---|
| Cientos de funciones publicas de `pg_catalog` | son ejecutables por cualquier rol conectado |
| Funciones de `public` con `EXECUTE` a `PUBLIC` | via el `USAGE` que el rol hereda de `PUBLIC` (`D07` + Salida 3) |
| `TEMPORARY` sobre la base | puede crear tablas, tipos y funciones **temporales** (`A14`) |
| Consumo de recursos | conexiones, CPU, memoria de sesion, `pg_sleep`, joins caros sobre catalogos |

**El limiter de B4 protege los ENTRYPOINTS, no la conexion.** Cuota, nonce y ticket
se cobran cuando el atacante llama `api_precios_admitir`. Si abre una sesion y hace
otra cosa, el limiter **no interviene**.

**Lo que el atacante NO puede hacer** (esto si esta cerrado, y medido):

| | Check |
|---|---|
| Leer o escribir **una sola tabla** de negocio: cero privilegios de tabla y de secuencia | `D05` + `D06` + gate precommit |
| Llamar al **motor B3** directo y saltear cuota + nonce + ticket | `D04` (13 `precios_*` owner-only) |
| Escalar via un `SECURITY DEFINER` ajeno **invocable** | `D03` + gate precommit |
| **Crear** objetos persistentes: ni en `public`, ni schemas nuevos | `A11` + `A13` |
| Envenenar `pg_temp` para secuestrar una llamada | **D3** (`api_precios_guard_sesion`) |
| Correr computo ilimitado **a traves de los entrypoints** | cotas estructurales |

**En claro:** una credencial filtrada **no da acceso a los datos ni al negocio**.
Da una sesion SQL con la que se puede molestar (consumir recursos, leer catalogos,
llamar funciones publicas ajenas). Eso se mitiga en la capa de red y de conexiones
(Supavisor, pool limits, rotacion de password), **no** desde B4-0A.

`D07` y `A14` se conservan en el VERIFY **como evidencia de esa superficie**, no
como fallos.

### Cotas de tiempo y de computo

| Mecanismo | Estado real (medido) |
|---|---|
| `lock_timeout` en `proconfig` | **cota dura.** Se reimpone aunque el caller haga `SET lock_timeout = 0`. |
| `statement_timeout` en `proconfig` | **inerte.** No arma el timer si el caller puso `0`, ni baja uno ya armado. **Por eso no esta.** |
| `SET LOCAL statement_timeout` desde la Edge | **la unica forma** de acotar el tiempo de ejecucion. |
| Limite de 8 KB del payload | evita el parse JSONB / hash / ticket. **No** es limite de transporte frente a acceso directo a PG. |
| **Cotas estructurales** | **la defensa server-side real de computo.** Span <= 30 noches, horizonte <= hoy+540, `fecha_in` >= hoy (ART), personas 1-20, reject-unknown. |

Frente a acceso directo a PG, al atacante **no** lo limita `statement_timeout` (lo
pone la Edge, que no esta en el camino). Lo limitan las **cotas estructurales**, que
viven dentro de las funciones.

### `now()` vs `clock_timestamp()`

Todo lo temporal-de-seguridad usa `clock_timestamp()`. **Medido:** con una TXN2
abierta mientras el ticket todavia era valido, `expires_at > now()` devolvio
**`True`** para un ticket vencido hacia un segundo. `now()` es
`transaction_timestamp()`: queda **congelado** al inicio de la transaccion.

### Ventana unica del rate limit

`api_precios_admitir` calcula `date_trunc('minute', clock_timestamp())` **una sola
vez** y la pasa a los dos consumos (global y sujeto). Sin eso, si el reloj cruza el
borde del minuto entre las dos llamadas, las cuotas caerian en ventanas distintas.

---

## 9.bis. Ledger de admision -- recuperacion de respuesta perdida

**El agujero que cierra.** TXN1 commiteaba, creaba el ticket y devolvia su `id`. Si
la Edge **perdia la respuesta** (timeout de red, crash, reciclado del pooler), el
ticket existia y el nonce estaba consumido, pero la Edge **no conocia el
`ticket_id`** -- y el rol **no puede leer la tabla de tickets**. Reintentar daba
`nonce_replay`. Estado **ambiguo e irrecuperable**: cuota cobrada, nonce quemado,
ticket huerfano.

**La solucion.** El nonce pasa a ser una **identidad durable de admision**:

```
api_precios_nonce_s2s
  (client_id, nonce)  ->  admission_hash   -- el binding
                      ->  ticket_id        -- el ticket que produjo
```

`admission_hash` **ES** el `request_hash` del ticket (mismo `ticket_hash_v1`): un
solo canon, no dos. **No incluye `correlation_id`**: un reintento con otro
`correlation_id` sigue siendo el **mismo request logico**.

### Semantica

| Caso | Resultado |
|---|---|
| Mismo nonce + **mismo** binding | **el MISMO `ticket_id`**, `via: 'recovery'` |
| Mismo nonce + binding **distinto** | `nonce_replay` |
| Recovery | **NO cobra cuota. NO vuelve a consumir nonce.** |
| Dos admisiones **concurrentes** | **UN SOLO ticket** (una `nuevo`, otra `recovery`) |
| Rechazado por **cuota** | **NO escribe el ledger** -> el nonce **no se quema** |
| Todo el ledger | **owner-only.** Cero grants de tabla (`G05`). |

### `ticket_estado` -- que hace la Edge con cada uno

El recovery devuelve tambien el estado del ticket recuperado:

| `ticket_estado` | Que significa | Que hace la Edge |
|---|---|---|
| `libre` | el ticket nunca se uso | **usarlo en TXN2** |
| `consumido` | TXN2 **ya corrio** | si es `congelar`: reintentar por `idem_key`. Si es `cotizar`/`obtener`: pedir admision nueva con **nonce nuevo**. |
| `vencido` | paso su ventana de 30 s | admision nueva con **nonce nuevo** |
| `inexistente` | el ticket fue **purgado** | admision nueva con **nonce nuevo** |

### El orden cambio, y por que

**Antes:** cuota -> nonce -> `[savepoint: parse + ticket]`.
**Ahora:** `[savepoint externo: validar -> tamano -> parse+hash -> LEDGER -> cuota -> ticket]`.

El hash **es** el binding del ledger, asi que hay que calcularlo **antes** de
consultarlo. Y el ledger hay que consultarlo **antes de cobrar**, porque un recovery
**no debe cobrar cuota**.

**Consecuencias declaradas:**

- Un **payload invalido** ya **no cobra cuota** y **no quema el nonce**. Antes si
  ("el sobredimensionado paga"). El trade-off es consciente: el parse queda acotado
  a **8 KB** por un check `octet_length` **O(1)** previo, y el vector de flood real
  -- **nonces nuevos y validos** -- sigue cobrando cuota.
- Un **rate_limited** ya no quema el nonce. Antes lo dejaba inservible sin darle un
  ticket: el cliente quedaba trabado.

### Concurrencia -- por que converge a un solo ticket

**Medido en PostgreSQL real:** `INSERT ... ON CONFLICT DO NOTHING` con una tupla
concurrente **no commiteada** **ESPERA** (0,71 s en la medicion) y despues ve el
conflicto. La perdedora lee la fila del ganador y devuelve **su** ticket.

---

## 10. Contrato de la Edge (B4-1)

> **NUEVO en v5 -- `via` y `ticket_estado`.** `api_precios_admitir` ahora puede
> responder `{"ok": true, "via": "recovery", "ticket_id": ..., "ticket_estado": ...}`.
> B4-1 **debe** manejarlo: `via: 'recovery'` significa que el ticket **ya existia**
> (respuesta perdida o carrera concurrente), y `ticket_estado` dice si se puede usar.
> Tratarlo como `nuevo` sin mirar `ticket_estado` puede llevar a llamar TXN2 con un
> ticket ya consumido. Ver la tabla de §9.bis.

```ts
// transaction pooler (6543), pool max 1, prepare:false, ssl require
const sql = postgres(CONN, { max: 1, prepare: false, ssl: 'require' })

// TXN1 -- admision. correlation_id SOLO aca.
await sql.begin(async tx => {
  await tx`SET LOCAL statement_timeout = '2s'`
  return tx`SELECT precios_api.api_precios_admitir(
    ${accion}, 's2s', 'whatsapp', ${nonce}::uuid,
    ${payloadString},               -- string JSON, NO objeto
    ${idemKey}::uuid, ${cotId}::uuid, ${correlationId}::uuid)`
})

// TXN2 -- ejecucion con el ticket.
await sql.begin(async tx => {
  await tx`SET LOCAL statement_timeout = '5s'`
  return tx`SELECT precios_api.api_precios_cotizar_exponer(${ticket}::uuid, ${payload}::jsonb)`
})
```

**Doble envelope privado.** El envelope EXTERIOR `ok:true` significa **"el gateway
ejecuto"**. El resultado del motor va en `motor.*`. B4-1 **debe inspeccionar
`motor.ok`** (y `motor.vigente` en obtener/replay). Puede existir, y es valido:

```json
{ "ok": true, "motor": { "ok": false, "error": "temporada_no_resuelta" } }
```

**Manejo de `VDT01` (`sesion_contaminada`):** la TXN2 hace rollback -> el ticket
vuelve a quedar **libre** -> la Edge **recicla la conexion** y **reintenta una sola
vez con el mismo ticket**. Si vuelve a fallar -> 503. No reintentar en loop.

| SQL devuelve | HTTP |
|---|---|
| `admision_invalida` / `payload_invalido` | 400 |
| `rate_limited` | 429 |
| `nonce_replay` / `conflicto` | 409 |
| `ticket_invalido` | 401 |
| `timeout` | 504 |
| `error_interno` | 500 |
| `VDT01` (excepcion) | 503 + reintento |

**DTO publico:** allowlist positiva **en la Edge**, nunca en SQL.
`resultado_motor_privado` no sale nunca.

---

## 11. Atomicidad de los jobs pg_cron -- lectura honesta

Los 4 `cron.schedule` se ejecutan **dentro de la transaccion, antes del unico
COMMIT**, con `to_regprocedure` verificando la firma exacta antes de programar.

`cron.schedule()` es un `INSERT` en `cron.job` + una senal al worker, **sin commit
interno documentado** -> participa de la transaccion del caller. En el harness, un
error tras los 4 schedule deja **cero jobs** tras el rollback.

**Lo que NO se puede garantizar desde el harness:** que la version de `pg_cron` de
Supabase respete esto en todos los casos. Por eso **no se afirma atomicidad
absoluta**. Si al terminar el paso 1 el VERIFY muestra `E01..E05` verdes, los jobs
quedaron bien. Si muestra menos de 4 jobs -> **correr el rollback** y volver a
empezar. El rollback es el compensatorio.

---

## 12. Retenciones

| Tabla | Elegible | Cron | Retencion maxima real | Indice de purga |
|---|---|---|---|---|
| `api_precios_ticket` | +5 min | `*/5` | **~10,5 min** | `(expires_at)` |
| `api_precios_nonce_s2s` | 10 min | `*/5` | **~15 min** | `(created_at)` |
| `api_precios_rate_limit` | 60 min | `*/10` | **~70 min** | `(ventana)` |
| `api_precios_idempotencia` | 24 h | `0 * * * *` | **~25 h** | `(created_at)` |

Las 4 purgas usan indice. **Sin watchdog** (`pg_terminate_backend` retirado).

---

## 13. Rollback

```
B4_0A_v5_ROLLBACK.sql
```

Elimina los 4 jobs, las 19 funciones, las 4 tablas, el schema `precios_api` y el
rol. **Conserva deliberadamente UNA sola cosa: el `REVOKE` de §9.bis** sobre las 13
`precios_*` (deja al motor B3 owner-only, que es el estado correcto). No deja la
base "exactamente como estaba", y no debe hacerlo.

> **No toca `pg_default_acl`.** B4-0A no aplica hardening global de default
> privileges, asi que no hay nada de eso que revertir. Este script no lo aplica ni
> lo deshace, y su VERIFY no lo mira: seria mezclar alcances.

- **Gate TEST como primera operacion:** aborta si `ambiente <> 'test'` **antes de
  tocar nada**. Probado: en `ops` no toca ni un job.
- **ATOMICO respecto del rol:** `DROP OWNED BY` + `DROP ROLE` estan **dentro de la
  misma transaccion**, antes del unico COMMIT. Si el `DROP SCHEMA` falla, **se
  revierte todo y el rol permanece**. (Antes estaban despues del COMMIT: un fallo
  del DROP SCHEMA borraba el rol igual y dejaba los objetos vivos.)
- **`DROP SCHEMA` sin CASCADE:** si quedara algo ajeno adentro, falla y hay que
  mirarlo. Un CASCADE lo borraria en silencio.
- **Firma exacta** de `cron.unschedule(text)` antes de desprogramar.
- Corre aunque `pg_cron` no exista y aunque B4-0A haya fallado a la mitad.
- Termina con 14 checks propios, incluidos los **fingerprints B2A/B2B/B3**.

---

## 14. Lo que B4-0A deja abierto -- declarado, no tapado

B4-0A **no aplica ningun hardening global**. No lo hace por omision: lo hace por
decision, porque un cambio global que su rollback no puede deshacer no pertenece a
este bloque.

**Queda abierto, y esta medido:**

Via el `USAGE` que el rol hereda del pseudo-rol `PUBLIC` sobre `public`, puede
invocar **cualquier funcion de `public` que tenga `EXECUTE` a `PUBLIC`** -- las que
ya existen y las que se creen en el futuro. `D07` las cuenta y la **Salida 3** las
lista una por una.

**Lo que NO queda abierto** (y por eso el residual es tolerable):

| | Check |
|---|---|
| Ninguna de esas funciones puede ser `SECURITY DEFINER` invocable -> **sin escalada** | `D03` |
| Ninguna puede ser del motor B3 -> **no se puede saltear cuota+nonce+ticket** | `D04` |
| Cero privilegios de tabla y de secuencia | `D05` + `D06` |
| El rol no puede **crear** nada: ni en `public`, ni schemas nuevos | `A11` + `A13` |

**Cerrar el residual exige hardening GLOBAL** (default privileges y/o revocar el
`USAGE` de `PUBLIC` sobre `public`). Eso es un frente aparte, con su propio
inventario, snapshot, verificacion de impacto sobre `anon` / `authenticated` /
`service_role` / `authenticator` y roles personalizados, y su propio rollback.
**No se disena ni se ejecuta desde aca.**

> **Medido, y por eso no se toca a la ligera:** revocar el `EXECUTE` por defecto a
> `PUBLIC` hace que `anon`, `authenticated` y `authenticator` **pierdan acceso a
> toda funcion nueva** expuesta por PostgREST, salvo que tengan grants propios.
> Solo sobrevive quien ya tiene un default privilege explicito. Aplicarlo sin
> auditar esos roles rompe el API **en silencio**.

---

## 15. Al cerrar B4-0B: retirar el probe

`api_precios_probe_ambiente()` existe **solo** para el probe de conexion de B4-0B:

```sql
REVOKE EXECUTE ON FUNCTION precios_api.api_precios_probe_ambiente() FROM vita_precios_api;
DROP FUNCTION precios_api.api_precios_probe_ambiente();
```

> El `DROP` es en **`precios_api`**, no en `public`.

Superficie final del rol: **4 `EXECUTE`**. Despues de esto `D01` debe dar **4**, no
5 -> ajustar `_allow` en el VERIFY. Y `C03` pasa a **4 DEFINER / 14 INVOKER**.

---

## 16. Que se valido, y donde

### Escenarios nuevos de v5 (los dos bloqueantes), medidos en PostgreSQL real

| Escenario | Resultado |
|---|---|
| TXN1 commitea y se **descarta la respuesta**; se reintenta | **mismo `ticket_id`**, `via=recovery`, `estado=libre` |
| El recovery, ¿cobra cuota o escribe filas? | **no**: tickets, ledger y cuota **inalterados** |
| El ticket recuperado, ¿sirve? | **si**: TXN2 con el ticket recuperado da `ok=true` |
| Replay con **binding distinto** | `nonce_replay` |
| Recovery con el ticket **ya consumido** | `via=recovery`, `estado=consumido` |
| **Dos admisiones concurrentes** (mismo nonce) | **UN SOLO ticket** (A=`nuevo`, B=`recovery`); 1 fila de ledger |
| **Rate limited** | **no** escribe el ledger -> el mismo nonce sirve despues |
| **Lock real** en la fila global del limiter (TXN1) | JSON limpio `error=timeout`; **cero** cuota parcial, ledger o ticket; retry OK; conexion usable |
| **Lock real** en la fila del ticket (TXN2) | JSON limpio `error=timeout`; **el ticket sigue LIBRE**; retry con el **mismo** ticket OK |
| ¿Escapo algun error PostgreSQL crudo? | **cero** |
| **Gate ACL precommit** con un SECDEF ajeno plantado | **aborta**, sin crear el schema |
| **Gate ACL precommit** con un privilegio de tabla plantado | **aborta** |
| **Rollback con `cron.job` DROPEADO** | corre sin fallar; `R05` PASS; residuo cero |

**Bug encontrado y cerrado durante esta ronda:** al meter el gate de ambiente dentro
del savepoint externo, su excepcion (`VDT03`) quedaba atrapada por el `WHEN OTHERS`
y se degradaba a `error_interno` en vez de abortar. Ahora `VDT01` **y** `VDT03`
re-lanzan explicitamente en los 4 entrypoints (`G04`).

**En PostgreSQL real (harness local, reproducible y portable):**

```bash
python3 -m pip install -r B4_0A_v5_requirements.txt
python3 B4_0A_v5_HARNESS.py --reset   # PG + pg_cron(stub) + roles + stubs B3/B2A/B2B
python3 B4_0A_v5_SMOKES.py            # 226 PASS / 0 FAIL
```

El harness no usa rutas absolutas (todo cuelga de la carpeta del script o de
`B4_PGDATA`). El `pg_cron` local es un **stub compatible**, no la implementacion real.

| Suite | Resultado |
|---|---|
| `B4_0A_v5_SMOKES.py` | **226 PASS / 0 FAIL** |
| `B4_0A_v5_VERIFY.sql` | **62 PASS / 3 FAIL** -- los 3 FAIL son los fingerprints |
| `B4_0A_v5_ROLLBACK.sql` | **11 PASS / 3 FAIL** -- idem; residuo cero |

Los smokes usan **dos identidades**: `admin()` para setup/asserts/teardown, y
`rol()` (via `SET SESSION AUTHORIZATION vita_precios_api`) para **toda** llamada
runtime y **todos** los negativos.

**Lo que NO se puede validar localmente (TEST-only):**

| Que | Por que |
|---|---|
| **Los 3 fingerprints** (`F02`, `F05a`, `F05b`, `R07`, `R10a`, `R10b`) | El harness usa **stubs** de B3/B2A/B2B (el motor real necesita `btree_gist`). **En TEST tienen que dar PASS.** Si alguno da FAIL en TEST -> algo toco el upstream -> **parar**. |
| `SET ROLE postgres rechazado` | El owner del harness es superuser y puede volver. Lo cubre B4-0B con la conexion autenticada real. |
| Jobs `pg_cron` reales + atomicidad | En el harness `pg_cron` es un stub. Ver §11. |
| Supavisor (6543, prepare:false, SSL) | Infra de Supabase -> B4-0B. |

---

## 17. Hard stop

Nada se ejecuta en Supabase hasta que apruebes los artefactos.

Despues del paso 3 (VERIFY en TEST), **parar**. B4-0B es una conversacion aparte.

---

## 18. Manifest -- SHA-256 (B4-0A v5, 7 archivos)

```
98cab96acc5f8990089899aaa910a54ba95c83e58092768f8a779a668f468ad1  B4_0A_v5_ROL_TABLAS_FUNCIONES.sql
bc2a24956d0afae1befc1f7e29bfea3c1a5ea1644c1b12e34b801b1363925aee  B4_0A_v5_VERIFY.sql
f9785494a8d414803d4b6f840d0cb1e3deaf243caacb3adf6e5c3e3dfadf4c89  B4_0A_v5_ROLLBACK.sql
(este archivo -- sha256sum B4_0A_v5_RUNSHEET.md)                  B4_0A_v5_RUNSHEET.md
fecbf806966bb72d8606c30f7c4c99a7cd81babff10c814ec17f488c02e1f9ef  B4_0A_v5_HARNESS.py
bf76f22a59956d79814c07670931ad9d19010f809212ee7b2db9abb03426e1d4  B4_0A_v5_SMOKES.py
a51ebc98a741b5ecec3dae0c1f554834c78be42824010002b4f2818cca90b50d  B4_0A_v5_requirements.txt
```

**Nombres versionados `v5`.** Los `v4` quedan RETIRADOS: si tenes archivos sin el
`v5` en el nombre, son viejos y no sirven. Esto evita la confusion de cache.

**LF-only.** ASCII puro salvo el SQL principal y este runsheet, con acentos **solo
en comentarios/prosa** (cero no-ASCII en codigo ejecutable). Cero project refs,
cero credenciales, cero PII.
