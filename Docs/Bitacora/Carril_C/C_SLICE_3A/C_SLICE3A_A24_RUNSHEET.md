# C_SLICE3A_A24_RUNSHEET.md — A24 `historico.reservas` (wrapper directo + smoke)

**Carril C / Slice 3a · Bloque A24 directo.** Wrapper n8n firmado + batería de smoke DIRECTO (sin gateway). **TEST exclusivamente** (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`). **No OPS. No writes. Read-only.**

Artefactos:
- `portal-a24-historico-reservas__TEMPLATE.json` — wrapper (sanitizado).
- `C_SLICE3A_A24_smoke_directo.ps1` — batería directa (seguridad + filtros + paginación + floor).

Estado al iniciar: A24 **no** cableado en el gateway todavía (eso es el bloque siguiente, recién con esta batería en verde).

---

## Contrato (recordatorio)

- **action:** `historico.reservas` · **wrapper:** `portal-a24-historico-reservas` · roles `{vicky, socio}`.
- **Buscador operativo de reservas** (no histórico contable): floor inferior duro `2026-07-01`, puede incluir reservas futuras (`fecha_hasta` default `null`), **no se usa para liquidación ni Carril B**, **no reemplaza A04** (calendario operativo).
- **Salida:** `data:{ filas:[...], limit, offset, total }`. Lista vacía → `filas:[]` con `ok:true` (D-C-47). `saldo_real` puede ser negativo (sobrecobro) y se reporta tal cual. Privacidad: nombre/teléfono/email; **sin** `dni` ni `notas_internas`.
- `saldo_real = monto_total − Σ(pagos confirmados sena/saldo)`, CTE desde `reservas.id_pre_reserva` (D-C-49, byte-alineada a A12).
- `total` = universo filtrado vía `COUNT(*) OVER()` (antes de LIMIT). *Caveat v1:* si `offset` supera el universo, la página vacía devuelve `total=0`; en uso normal (offset dentro de rango) es exacto.

---

## Pasos de ejecución (Franco)

**0. Gate de ambiente.** En Supabase TEST:
```sql
SELECT valor FROM configuracion_general WHERE clave = 'ambiente';   -- debe = 'test'
```

**1. Importar el wrapper.** Importá `portal-a24-historico-reservas__TEMPLATE.json` en n8n (`federicosecchi.app.n8n.cloud`).

**2. Credencial Postgres.** En los dos nodos Postgres (`leer_ambiente` y `PG: leer historico`), reemplazá la credencial placeholder `vita_supabase_test (reemplazar al importar)` por tu credencial **TEST** real.

**3. Secreto HMAC (Modo B, L-C-10).** En `validar_firma_ts_rol`, reemplazá `__PEGAR_SECRETO_O_USAR_VARIABLE__` por el `VITA_HMAC_SECRET` **de TEST**. El assert por prefijo aborta si quedó el placeholder. **No** lo dejes en el archivo commiteado.

**4. Activar el workflow.** El smoke pega al webhook de **producción** (`/webhook/portal-a24-historico-reservas`), así que el workflow debe estar **activo**. Es read-only y gated por ambiente: activarlo en TEST es seguro.

**5. Pre-check read-only (opcional, para fijar el `total` esperado).**
```sql
-- universo del buscador (con floor):
SELECT COUNT(*) AS desde_julio, MIN(fecha_checkin) AS min_cin, MAX(fecha_checkin) AS max_cin
FROM reservas WHERE fecha_checkin >= DATE '2026-07-01';

-- por cabana (con floor) -> para F4/F5:
SELECT id_cabana, COUNT(*) AS n
FROM reservas WHERE fecha_checkin >= DATE '2026-07-01'
GROUP BY id_cabana ORDER BY id_cabana;
```
*(Por S5, `desde_julio` debería ser 7. El happy `{}` debería devolver `total` = ese número.)*

**6. Editar y correr el smoke.** En `C_SLICE3A_A24_smoke_directo.ps1`:
- Pegá el **mismo** secreto en `$Secret`.
- Verificá `$BaseUrl` y `$Webhook`.
- Corré: `pwsh ./C_SLICE3A_A24_smoke_directo.ps1` (o PS 5.1).
- *(Opcional)* para un caso **positivo** de `texto`, editá F8 con un substring real de un huésped en TEST.

---

## Criterios de PASS

| # | Caso | Esperado |
|---|---|---|
| 1 | vicky `{}` | `ok:true` · `filas` presente |
| 2 | socio `{}` | `ok:true` · `filas` presente |
| 3 | jenny | `ok:false` · `rol_no_permitido` |
| 4 | intruso | `ok:false` · `rol_no_permitido` |
| 5 | firma equivocada | `ok:false` · `firma_invalida` |
| 6 | ts −10 min | `ok:false` · `ts_fuera_de_ventana` |
| 7 | `ambiente_esperado='ops'` | `ok:false` · `ambiente_incorrecto` |
| 8 | action `cobranza.saldos` | `ok:false` · `accion_desconocida` |
| F1 | sin filtros | `ok:true` · `filas`+`total`+`limit=50`+`offset=0` |
| F2 | `fecha_desde=2026-07-10` | todas `fecha_checkin >= 2026-07-10` |
| F3 | `fecha_desde=2026-06-01` | **0 filas < 2026-07-01** (regresión de floor) |
| F4 | `id_cabana=5` | todas `id_cabana=5` |
| F5 | `id_cabana=3` (Arrebol) | `filas:[]` con `ok:true` |
| F6 | `estado=confirmada` | todas `confirmada` |
| F7 | `estado=completada` | `filas:[]` con `ok:true` |
| F8 | `texto` sin match | `filas:[]` con `ok:true` |
| F9 | `limit=2 offset=0` | `≤2` filas · `total` presente |
| F10 | `limit=2 offset=2` | página distinta de F9 (ids no se solapan) |
| P1 | clave no permitida | `payload_invalido` |
| P2 | fecha mal formada | `payload_invalido` |
| P3 | estado fuera de enum | `payload_invalido` |
| P4 | `id_cabana=1.5` | `payload_invalido` |
| P5 | `fecha_hasta < fecha_desde` | `payload_invalido` |
| P6a | `payload` string | `payload_invalido` (no se coerciona a `{}`) |
| P6b | `payload` array | `payload_invalido` |
| META | allowlist | todos los `error.code` en la allowlist del gateway |

**Cierre del bloque A24 directo** = **todo en verde** (8/8 seguridad + 10/10 funcionales + 7/7 payload + META, sin códigos fuera de allowlist). Recién entonces avanzamos al **cableado en el gateway** (extender `portal-api` desde `C_SLICE2_A10_portal-api_index.ts` con `payloadHistoricoReservas` + entrada CATALOG, `isWrite` ausente).

---

## Anti-leak / disciplina

- Borrar el secreto de `$Secret` **antes** de commitear el `.ps1`. El template ya está sanitizado (placeholder de secreto + credencial).
- No tocar OPS, ni el canónico, ni `dispatchN8n`/`buildSignedEnvelope`/`actorCoherente`/allowlist del gateway (este bloque es solo wrapper directo).
- Si algún caso falla, pegame la salida del smoke (PASS/FAIL + códigos vistos) y lo diagnostico antes de seguir.

---

## Verificación previa hecha por Claude (antes de pasarte esto)

- JSON del wrapper: válido (re-parseado) + anti-leak (sin `sb_secret_`, sin URLs con credenciales).
- Los 3 nodos JS (`validar_firma_ts_rol`, `verificar_acceso`, `render`): `node --check` OK.
- SQL inline de A24: parsea contra la gramática real de Postgres (`libpg_query`).
- `.ps1`: ASCII puro (0 bytes > 127), llaves/paréntesis balanceados. *(El parse-check de PowerShell corré vos; acá no hay `pwsh`.)*
