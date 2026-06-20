# C_SLICE2 / A10 -- RUNSHEET wrapper directo `portal-a10-registrar-saldo__TEST`

Estado: wrapper directo CONSTRUIDO y validado en banco (Node + dry-parse). NO importado aun.
Esto NO extiende `portal-api`, NO toca OPS, NO cierra Slice 2, NO propaga satelites.

Orden acordado: wrapper directo -> test de logica (Node) -> dry-parse SQL -> import n8n ->
confirmacion de credencial/privilegios -> smokes directos. Recien despues, gateway.

---

## 0) Condicion #1 -- SQL de saldo real (RESUELTA: byte-alineado a A12)

Con el RUNSHEET de B10 (seccion 5) ya tengo el SQL real de A12. La capa de saldo de A10 quedo
**BYTE-ALINEADA a A12 (D-C-49 / L-C-14)**: mismos nombres de CTE (`reserva_por_prereserva`,
`pagos_reserva_normalizados`), misma `COALESCE(p.id_reserva, via prereserva)` y mismo
`FILTER (WHERE estado='confirmado' AND tipo IN ('sena','saldo'))` dentro del `SUM`. Verificable
en `A10_pg_cobranza.sql` (CTEs 3-6) y `A10_pg_verif_post.sql`:

- `total_pagado_confirmado = SUM(monto_recibido) FILTER (estado='confirmado' AND tipo IN ('sena','saldo'))`
  sobre `pagos_reserva_normalizados` filtrado por `id_reserva_normalizado = id_reserva objetivo`.
- `saldo_real = reservas.monto_total - total_pagado_confirmado`.
- normalizacion por `COALESCE(p.id_reserva, reserva_por_prereserva.id_reserva)`.
- `reserva_por_prereserva` agrupada por `id_pre_reserva` con `MIN(id_reserva)` (CTE, no escalar).
- nunca usa `reservas.monto_saldo`.

Diferencia respecto de A12 (intencional): A12 LISTA todas las reservas con `saldo>0` (LEFT JOIN +
GROUP BY + HAVING + JOIN a cabanas/huespedes). A10 computa el saldo de UNA reserva objetivo
(filtro `id_reserva_normalizado = $1->>'id_reserva'`) y traduce el universo `estado IN
('confirmada','activa') AND saldo>0` a ramas de rechazo explicitas en el CASE
(`estado_no_cobrable`, `saldo_ya_cancelado`) porque un write necesita DISTINGUIR el motivo.
Las CTEs de normalizacion (`reserva_por_prereserva`, `pagos_reserva_normalizados`) son identicas
a A12. Eleccion deliberada (L-C-14): para un write que decide sobrepago conviene la normalizacion
por-prereserva de A12 (superset mas completo) y no la de A05 (solo `id_reserva`).

Nota molde L-C-15 (incorporada en esta revision): `leer_ambiente` y `PG_verif_post` (lecturas)
llevan `onError:continueRegularOutput` + `alwaysOutputData` + `executeOnce` -> degradan a envelope
limpio en vez de colgar. `PG_cobranza` (write) usa `onError:continueErrorOutput` -> rutea P0001 de
`abortar_si_falla` a `render_error_pg` (`error_interno`, retry seguro por idempotency_key).
Y el `render`: como `abortar_si_falla` (D-9B-19) ya garantiza `confirmado`, `resultado.ok===true`
es confirmacion autoritativa; `verif` solo enriquece `saldo_real_actual` y, si degrada, NO baja a
`estado_incierto`.

Limite del dry-parse: pglast usa el parser REAL de Postgres (libpg_query) -> valida sintaxis y
gramatica reales, NO semantica de catalogo (existencia de columnas/funciones). Esa capa la
confirmas vos al importar contra TEST (las funciones/columnas existen: A12 corrio con filas=3 reales).

---

## 1) Antes de importar -- check de privilegios (condicion #2)

Correr **desde la credencial Postgres de n8n TEST (`vita_supabase_test`)**, NO desde el SQL Editor
con otro rol. Archivo: `A10_privilege_check.sql`.

```sql
SELECT
  has_function_privilege('public.registrar_pago(jsonb)'::regprocedure, 'EXECUTE') AS puede_registrar_pago,
  has_function_privilege('public.abortar_si_falla(jsonb)'::regprocedure, 'EXECUTE') AS puede_abortar_si_falla;
```

Si alguna da `false` => **FRENAR**. No importar ni correr smokes hasta resolver el privilegio
(el nodo PG_cobranza no podria ejecutar `registrar_pago` / `abortar_si_falla`).

---

## 2) Puntos de verificacion al importar (5)

**(a) Binding de `$1` a AMBAS sentencias del nodo PG_cobranza (queryBatching: transaction).**
Diseno PRIMARIO (entregado): St1 y St2 comparten un solo `$1` = `sql_payload` jsonb, con
`queryReplacement = {{ JSON.stringify($json.sql_payload) }}`. Esto exige que n8n reaplique el
mismo `$1` a cada sentencia del batch.
- Verificar con la corrida FELIZ (paso A de Bloque 3): si devuelve `ok:true`, el binding anda.
- **FALLBACK documentado** (si n8n consume parametros posicionalmente a lo largo del batch y
  St2 no recibe `$1`): cambiar a dos parametros.
  - St1: `SELECT pg_advisory_xact_lock( hashtext('a10_cobranza_saldo:' || $1::text) );`
  - St2: reemplazar TODO `$1` por `$2`.
  - `queryReplacement = {{ [$json.id_reserva, JSON.stringify($json.sql_payload)] }}`  (=> $1=id_reserva, $2=payload)
  Exactamente una de las dos variantes funciona en tu n8n; la FELIZ lo dirime en una corrida.
  CLAVE de correctitud: St1 y St2 DEBEN seguir siendo dos sentencias separadas (no fusionar):
  el snapshot READ COMMITTED de St2 se toma DESPUES de adquirir el lock en St1, y eso es lo que
  evita el doble cobro (un solo statement tomaria el snapshot antes del lock y romperia C2).

**(b) Privilegios** -- ver seccion 1 (gate duro previo a import).

**(c) Fidelidad byte del raw body.** El nodo Webhook tiene `Raw Body` ON; `validar_firma_ts_rol`
recomputa HMAC sobre los bytes crudos. La corrida FELIZ es el CANARIO: una firma valida solo
pasa si el raw se leyo byte a byte. Si FELIZ vuelve `firma_invalida` con secreto correcto =>
revisar como expone n8n el raw (binario `binary.data.data` vs `json.body`); el validador prueba
ambos, pero confirmalo en esa primera corrida.

**(d) URL del webhook (prod vs test).**
- Workflow `active:true` -> URL produccion: `<base>/webhook/portal-a10-registrar-saldo__TEST`.
- Workflow inactivo + "Listen for test event" -> URL test: `<base>/webhook-test/portal-a10-registrar-saldo__TEST`
  (solo responde mientras esta escuchando).
Setear `VITA_A10_WEBHOOK_URL` a la que uses. (`<base>` = `https://federicosecchi.app.n8n.cloud`.)

**(e) Precondicion de concurrencia: W09 inactivo.** El advisory lock cubre A10-vs-A10 unicamente.
El flujo viejo `vita_w09_cobranza_posterior` (form, no atomico, D-9B-07) NO toma este lock.
Antes de Bloque 5 (y de cualquier smoke que escriba), confirmar que W09 esta **INACTIVO** en TEST
y que ningun otro flujo cobra saldo sobre los fixtures 9900001..9900007.

---

## 3) Variables de entorno para los smokes (PowerShell)

```
$env:VITA_A10_WEBHOOK_URL  = '<la URL del punto (d)>'
$env:VITA_HMAC_SECRET_TEST = '<secreto HMAC de TEST>'   # NUNCA commitear; solo en la sesion
```

Los `.ps1` son ASCII puros (PS 5.1 / CP1252), sin `-Parallel` (Bloque 5 usa RunspacePool),
sin `if` inline en `-ForegroundColor`. Firman HMAC-SHA256 hex sobre los bytes UTF-8 del body,
identico a `buildSignedEnvelope` del gateway, y envian exactamente los bytes firmados.

---

## 4) LISTA EXACTA de smokes directos (orden de ejecucion)

### Bloque 0 -- Privilegios (SQL, credencial n8n TEST)
- `A10_privilege_check.sql` -> ambas columnas `true`. Si no, FRENAR.

### Bloque S0 -- Setup (SQL, TEST)
- `A10_setup.sql` -> **IDEMPOTENTE / self-cleaning**: tras el guard anti-OPS limpia el namespace
  `portal_test_a10_%` (orden FK-safe log_cambios->pagos->reservas->huespedes) y recien inserta.
  Re-correrlo NO duplica senas. Crea huesped centinela 9900000 y reservas 9900001..9900007 con sus senas.
  saldo_real esperado: 9900001=70000(confirmada), 9900002=70000(confirmada), 9900003=100000(activa),
  9900004=cancelada, 9900005=0(saldada), 9900006=70000(retry-race), 9900007=90000(over-race).

### Bloque 1 -- Seguridad (PS, sin escritura): `A10_smoke_seguridad.ps1`
32 casos (todos rebotan ANTES del PG; no escriben):
- S01-S03 firma (no coincide / ausente / formato) -> `firma_invalida`
- S04-S05 ts viejo/futuro (>300s) -> `ts_fuera_de_ventana`
- S06 action distinta -> `payload_invalido`
- S07-S08 rol jenny/basura -> `rol_no_permitido`
- S09 actor fuera de enum -> `payload_invalido`; S10 actor incoherente -> `rol_no_permitido`
- S11 sobre clave extra -> `payload_invalido`; S12 nonce ausente -> `payload_invalido`
- S13 ambiente_esperado=ops -> `ambiente_incorrecto`
- S14-S20 spoof en payload (actor/tipo/source_event/estado_inicial/validado_por/monto_esperado/id_pre_reserva) -> `payload_invalido`
- S21-S22 id_reserva cero/string -> `payload_invalido`
- S23-S27 monto cero/string/3-decimales/fuera-de-rango/Infinity -> `payload_invalido`
- S28 medio mp_link (no expuesto) -> `payload_invalido`; S29 medio invalido -> `payload_invalido`
- S30-S32 idempotency_key corta/larga/charset -> `payload_invalido`

### Bloque 2 -- Gate residual PRE (SQL): `A10_gate_residual.sql`
- Esperado `pagos_a10_smoke=0`, `log_a10_smoke=0` (Bloque 1 no escribio; fixtures de setup NO cuentan).

### Bloque 3 -- Funcional (PS, escribe): `A10_smoke_funcional.ps1`
Orden A,B,C,D,Da,F sobre 9900001 (saldo decreciente + idempotencia); E,G,H,I aparte.
- A FELIZ      9900001 paga 50000          -> ok, idempotent_match:false, saldo 20000
- B RETRY      9900001 paga 50000 misma key -> ok, idempotent_match:true, mismo id_pago, saldo 20000
- C MISMATCH   9900001 monto 60000 misma key -> `conflicto` (sin escritura)
- D MISMATCH   9900001 medio efectivo misma key -> `conflicto` (sin escritura)
- Da MISMATCH-ACTOR 9900001 misma key/monto/medio, actor franco (vs vicky de A) -> `conflicto` (sin escritura)
- F SOBREPAGO  9900001 paga 30000 (>20000) -> `conflicto`
- E COMPLETA   9900002 paga 70000          -> ok, saldo 0
- G SALDADA    9900005 paga 10000 (saldo 0) -> `conflicto`
- H CANCELADA  9900004                      -> `conflicto`
- I ACTIVA     9900003 paga 40000          -> ok, saldo 60000

### Bloque 4 -- Verificacion de escrituras (SQL): `A10_verif_writes.sql`
- Esperado: 9900001=1 pago (A, confirmado, 50000), 9900002=1 (E, 70000), 9900003=1 (I, 40000);
  C/D/F/G/H sin pago A10.

### Bloque 5 -- Concurrencia (PS, RunspacePool): `A10_smoke_concurrencia.ps1`
- C1 retry-race  9900006: 8 pedidos, MISMA key/monto 50000 -> exactamente 1 escritura nueva,
  7 idempotentes, un unico id_pago. (Verif SQL: 9900006 -> 1 pago, saldo 20000.)
- C2 sobrepago-race 9900007: 4 pedidos de 30000, keys DISTINTAS -> 3 ok + >=1 `conflicto`.
  (Verif SQL: 9900007 -> 3 pagos, saldo final 0.)

### Bloque 6 -- Meta allowlist (PS)
- Incluido al final de Bloque 1 y Bloque 3 (`Assert-AllowlistMeta`): TODO `error.code` visto debe
  pertenecer a la allowlist del gateway. Si aparece `__http_error__`/`__network_error__` => el
  wrapper no devolvio 200+envelope (revisar, viola D-C-35).

### Bloque 7 -- Teardown (SQL, TEST): `A10_teardown.sql`
- Borra FK-safe todo el namespace `portal_test_a10_%` + huesped centinela.

### Bloque 8 -- Gate POST (SQL): `A10_gate_post.sql`
- Esperado TODO en 0 (pagos/log/reservas/huespedes del namespace).

---

## 5) Criterio de aceptacion del wrapper directo (condicion #5) -- estado

- [x] JSON/template sanitizado sin secretos (barrido limpio).
- [x] HMAC placeholder con assert por prefijo (`__PEGAR_SECRETO_HMAC_TEST__`, `startsWith('__PEGAR_')`).
- [x] `active:false`.
- [x] Credenciales placeholder / TEST (`__CREDENTIAL_ID__` + `vita_supabase_test`).
- [x] SQL con guard anti-OPS en setup/teardown (DO block: `RAISE EXCEPTION` si ambiente <> 'test').
- [x] Scripts PS ASCII puro (0 no-ASCII; 0 byte 0x94).
- [x] Dry-parse VERDE (parser real PG; St1/St2 por separado + DML interno de setup/teardown).
- [x] Lista exacta de smokes directos (seccion 4).
- [x] Test de logica del validador en Node: 51 PASS / 0 FAIL.

---

## 6) Gateway (FUTURO -- NO ahora) -- recordatorio condicion #3

Cuando se extienda `portal-api` con `cobranza.registrar_saldo`:
- CATALOG: `{ handler:'n8n', roles:['vicky','socio'], webhook:'portal-a10-registrar-saldo__TEST',
  validate: payloadRegistrarSaldo, injectActor:true, isWrite:true }`.
- Assert OBLIGATORIO de regresion: SOBREPAGO via gateway debe volver `error.code='conflicto'`,
  NUNCA `estado_incierto`, y NO escribir pago. (El riesgo original era que un codigo externo no
  permitido se enmascarara como `estado_incierto` por la rama `noConfiable` de `dispatchN8n` para
  acciones `isWrite`. El render del wrapper ya mapea todo a la allowlist; este assert lo prueba.)
