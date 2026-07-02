# Runsheet — Promoción a OPS del backend de Cuenta Corriente (Bloque 2)

Promoción del **backend** de las lecturas L1 + L2 a **OPS**. Solo lecturas (read-only): no escribe
datos, no consume secuencias. El frontend ya está en `main`; se "prende" en OPS al final, con el
gateway.

**Orden (no romper el grid):** funciones → workflows → smoke de workflows → gateway. Las funciones
tienen que existir antes de que los workflows las consulten; los workflows antes de que el gateway
rutee a ellos.

> Convención OPS confirmada en el relevamiento: **todos los webhooks de OPS llevan sufijo `__OPS`**.
> Los workflows y el gateway de este paquete ya vienen con `__OPS`.

---

## 0. Confirmar entorno

En Supabase, confirmá que estás en el proyecto **OPS** (`lpiatqztudxiwdlcoasv`). Como doble
chequeo, en el SQL Editor podés seleccionar solo el PRE-CHECK de `PROMO_CC_FUNCIONES_OPS.sql` y
correrlo: debe devolver `ambiente_actual = ops`.

## 1. Funciones SQL

`PROMO_CC_FUNCIONES_OPS.sql` en el SQL Editor de OPS, con **nada seleccionado** (script completo).
Crea `cuenta_corriente_viva` y `cuenta_corriente_detalle` (DDL idéntico al validado en TEST,
idempotente, revocadas). "destructive query / Success. No rows returned" es normal (el `DROP`).

## 2. Workflows (n8n)

Importá los dos (**Import from File**):
- `portal-a27-cuenta-corriente__OPS.json`
- `portal-a28-cuenta-corriente-detalle__OPS.json`

En **cada** uno:
- Nodo `validar_firma_ts_rol`: pegá el secreto HMAC de **OPS** (reemplazá `__PEGAR_SECRETO_O_USAR_VARIABLE__`).
- Nodos Postgres (`leer_ambiente` y `PG: leer ...`): seleccioná la credencial de Supabase **OPS**.
- **Activá** el workflow.

Los webhooks quedan en `.../webhook/portal-a27-cuenta-corriente__OPS` y
`.../webhook/portal-a28-cuenta-corriente-detalle__OPS`.

## 3. Smoke de workflows (valida los workflows OPS, sin gateway)

En cada smoke, poné el secreto de **OPS** en `$Secret` y corré:

```
powershell -ExecutionPolicy Bypass -File portal-a27-cuenta-corriente__OPS_smoke_directo.ps1
powershell -ExecutionPolicy Bypass -File portal-a28-cuenta-corriente-detalle__OPS_smoke_directo.ps1
```

Cada uno trae un **GUARD OPS** (frena con exit 3 si el webhook no termina en `__OPS` o el ambiente
no es `ops`). Esperado: **todo PASS**, igual que en TEST pero con ambiente `ops` (el caso "ambiente
cruzado" ahora manda `test` y espera `ambiente_incorrecto`). Son read-only: solo consultan, no
escriben nada en OPS.

## 4. Gateway (Edge Function)

`portal-api_A28_OPS_index.ts` = copia del gateway **OPS A26** + tres cosas aditivas: el validador
`payloadCuentaCorrienteDetalle` y las entradas `cuenta_corriente.al_dia` (→ `portal-a27-...__OPS`)
y `cuenta_corriente.detalle` (→ `portal-a28-...__OPS`). Nada existente cambia (verificado por
reversa idéntica). Reemplazá el `index.ts` de `portal-api` en OPS por este archivo y deployá:

```
supabase functions deploy portal-api
```

En cuanto deploya, A02 empieza a listar las dos acciones para el rol **socio** (deriva del CATALOG),
y el frontend (ya en `main`) muestra "Socios → Cuenta corriente / Detalle mensual" en OPS.

---

Cuando corras los smokes del paso 3 y me pases los resúmenes, verifico. El **Bloque 3** es la
verificación end-to-end: smoke vía gateway OPS (con auth, como socio) y chequeo en vivo de las dos
pantallas en OPS. Después va el **Bloque 4** (canónico + satélites + acuñar `D-CC-*`/`L-CC-*`).
