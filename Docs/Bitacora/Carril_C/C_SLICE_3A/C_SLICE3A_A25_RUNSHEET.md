# C_SLICE3A_A25_RUNSHEET.md — A25 `ingresos.cobrados_periodo` (wrapper directo + smoke)

**Carril C / Slice 3a · Bloque A25 directo.** Wrapper n8n firmado + batería de smoke DIRECTO (sin gateway). **TEST exclusivamente** (`bdskhhbmcksskkzqkcdp`). **No OPS. No writes. Read-only.**

Artefactos:
- `portal-a25-ingresos__TEMPLATE.json` — wrapper (sanitizado).
- `C_SLICE3A_A25_smoke_directo.ps1` — batería directa (seguridad + caja/cuadre/floor + payload).

---

## Contrato (recordatorio)

- **action:** `ingresos.cobrados_periodo` · **wrapper:** `portal-a25-ingresos` · roles `{vicky, socio}`.
- **Caja percibida** (D-9G-03): `total_cobrado` = **solo `sena`+`saldo` confirmados**, bucket por mes de `created_at` (criterio Carril B vigente, sin conversión adicional). Suma sobre **pagos** (incluye el residuo); `cabana` por LEFT JOIN (null en el residuo).
- **`otros_movimientos`** (`extra`/`ajuste`/`reembolso`) **informativo**: no suma, no neto, no cascada, no matriz, no reabre Carril B (D-C-27).
- **Floor `2026-07-01`** (D-NEG-02): `periodo_desde` se recorta al floor.
- **`periodo_hasta` híbrido:** omitido → hoy (`CURRENT_DATE`), **sin** check de inversión (con floor futuro queda `periodo_desde > periodo_hasta` → vacío con `ok:true`); explícito → debe ser `>= periodo_desde` tras el clamp, sino `payload_invalido`.
- **Contrato:** `data:{ periodo_desde, periodo_hasta, total_cobrado, total, por_tipo[], por_medio[], por_mes[], otros_movimientos:{por_tipo[]}, filas[], limit, offset }`.
- **`filas` es PAGINADA** (`limit`/`offset`): `total_cobrado`, `por_tipo`, `por_medio` y `por_mes` son del **período completo**; `filas` trae **solo la página**. Por eso el cuadre `Σ filas = total_cobrado` **solo aplica cuando la página trae todo el universo** (como en el smoke con `limit=200`). En cambio `Σ por_medio = Σ por_tipo = total_cobrado` vale **siempre**.
- Hereda C1 (payload no-objeto → `payload_invalido`) y C2 (IDs `BIGINT` → número).

**Importante (hoy):** hoy es **2026-06-20** y el floor es **2026-07-01** (futuro). El default `{}` devuelve **vacío con `ok:true`** (`total_cobrado=0`). Los datos seeded de TEST están en julio/noviembre 2026, así que el smoke usa un `periodo_hasta` explícito (`2026-12-31`) para los casos con datos.

---

## Pasos de ejecución (Franco)

**0. Gate de ambiente.**
```sql
SELECT valor FROM configuracion_general WHERE clave = 'ambiente';   -- debe = 'test'
```

**1. Importar el wrapper** `portal-a25-ingresos__TEMPLATE.json` en n8n.

**2. Credencial Postgres.** En `leer_ambiente` y `PG: leer ingresos`, reemplazá la credencial placeholder por tu credencial **TEST**.

**3. Secreto HMAC (Modo B, L-C-10).** En `validar_firma_ts_rol`, reemplazá `__PEGAR_SECRETO_O_USAR_VARIABLE__` por el `VITA_HMAC_SECRET` **TEST**. No lo dejes en el archivo commiteado.

**4. Activar el workflow** (el smoke pega al webhook de producción `/webhook/portal-a25-ingresos`; read-only, gated por ambiente).

**5. Pre-check read-only (cruce contra S8/S9, para fijar las expectativas).**
```sql
-- caja percibida floored por mes (G3): julio 670200, noviembre 251000
SELECT to_char(date_trunc('month', created_at),'YYYY-MM') AS mes,
       SUM(monto_recibido) AS caja, COUNT(*) AS n
FROM pagos
WHERE estado='confirmado' AND tipo IN ('sena','saldo')
  AND created_at >= DATE '2026-07-01' AND created_at < DATE '2027-01-01'
GROUP BY 1 ORDER BY 1;

-- por medio (G4): efectivo 300200, transferencia_bancaria 621000
SELECT medio_pago, SUM(monto_recibido) AS monto, COUNT(*) AS n
FROM pagos
WHERE estado='confirmado' AND tipo IN ('sena','saldo')
  AND created_at >= DATE '2026-07-01' AND created_at < DATE '2027-01-01'
GROUP BY 1 ORDER BY 1;

-- otros (informativo, G5): extra 8500
SELECT tipo, SUM(monto_recibido) AS monto, COUNT(*) AS n
FROM pagos
WHERE estado='confirmado' AND tipo IN ('extra','ajuste','reembolso')
  AND created_at >= DATE '2026-07-01' AND created_at < DATE '2027-01-01'
GROUP BY 1 ORDER BY 1;
```
*(`total_cobrado` esperado = 670200 + 251000 = **921200**, sobre **4** pagos.)*

**6. Editar y correr el smoke.** En `C_SLICE3A_A25_smoke_directo.ps1`: pegá el mismo secreto en `$Secret`, verificá `$BaseUrl`/`$Webhook`, corré y **pegame la salida PASS/FAIL completa**.

---

## Criterios de PASS

| # | Caso | Esperado |
|---|---|---|
| 1 | vicky `{}` | `ok:true` (default vacío hoy, total_cobrado=0) |
| 2 | socio `{}` | `ok:true` |
| 3 | jenny | `rol_no_permitido` |
| 4 | intruso | `rol_no_permitido` |
| 5 | firma equivocada | `firma_invalida` |
| 6 | ts −10 min | `ts_fuera_de_ventana` |
| 7 | `ambiente_esperado='ops'` | `ambiente_incorrecto` |
| 8 | action `cobranza.saldos` | `accion_desconocida` |
| G1 | `periodo_hasta=2026-12-31` | `total_cobrado=921200`, `total=4` |
| G2 | cuadre (con `limit=200`) | `Σ por_medio = Σ por_tipo = Σ filas = total_cobrado`; `Σ por_medio = Σ por_tipo = total_cobrado` vale siempre |
| G3 | `por_mes` | julio 670200 · noviembre 251000 |
| G4 | `por_medio` | efectivo 300200 · transferencia 621000 |
| G5 | `otros_movimientos` | extra 8500, **NO sumado** (total sigue 921200) |
| G8 | `por_tipo` | solo `sena`/`saldo` |
| G6 | default `{}` | `total_cobrado=0`, `filas:[]` (floor futuro) |
| G7 | `periodo_desde=2026-06-01` | recortado al floor → `total_cobrado=921200` |
| G9 | `limit=1` | `≤1` fila · `total=4` |
| G10 | `limit=2 offset=2` | página distinta de G9 |
| P1 | clave no permitida | `payload_invalido` |
| P2 | `periodo_desde` mal formado | `payload_invalido` |
| P3 | inversión explícita | `payload_invalido` |
| P4 | `periodo_hasta` mal formado | `payload_invalido` |
| P5 | `limit` no entero | `payload_invalido` |
| P6a/P6b | `payload` string / array | `payload_invalido` |
| META | allowlist | todos los `error.code` en la allowlist |

**Cierre del bloque A25 directo** = **todo en verde** (8 seguridad + 10 funcionales + 7 payload + META). Recién entonces avanzamos al **cableado en el gateway** (validador `payloadIngresosPeriodo` con el mismo híbrido de `periodo_hasta`; entrada CATALOG `ingresos.cobrados_periodo`; `isWrite` ausente).

---

## Anti-leak / disciplina

- Borrar el secreto de `$Secret` antes de commitear el `.ps1`. El template ya está sanitizado (placeholder de secreto + credencial).
- No tocar OPS, ni el canónico, ni el gateway (este bloque es solo wrapper directo).
- Si algún caso falla, pegame la salida + códigos vistos y lo diagnostico antes de seguir.

---

## Verificación previa hecha por Claude (antes de pasarte esto)

- JSON del wrapper: válido (re-parseado) + anti-leak (placeholder `__PEGAR_` presente, sin `sb_secret_`/credenciales).
- Los 3 nodos JS (`validar_firma_ts_rol`, `verificar_acceso`, `render`): `node --check` OK.
- SQL inline de A25: parsea contra la gramática real de Postgres (`libpg_query`).
- **Render ejecutado con datos mock de S8/S9 → reproduce al centavo:** `total_cobrado=921200`, julio 670200, nov 251000, `por_medio` efectivo 300200 / transferencia 621000, `otros_movimientos` extra 8500 (separado, no sumado), residuo con `cabana`/`id_reserva` null, IDs como número, cuadre cerrado.
- `.ps1`: ASCII puro (0 bytes > 127), CRLF, llaves/paréntesis balanceados, `HttpWebRequest`+TLS 1.2. *(El parse-check de PowerShell corré vos.)*
