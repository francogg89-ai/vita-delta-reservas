# C_SLICE3A_A25_DIRECTO_CIERRE.md

**Carril C / Portal Operativo Interno — Slice 3a · Bloque A25 directo. CERRADO EN VERDE.**
Fecha de cierre: 2026-06-20.

## Alcance
- Acción nueva de **lectura**: `ingresos.cobrados_periodo` (caja percibida por período).
- Wrapper n8n: **`portal-a25-ingresos`** (firmado HMAC, camino directo sin gateway).
- **TEST exclusivamente** (`bdskhhbmcksskkzqkcdp`).

## Evidencia (smoke directo `C_SLICE3A_A25_smoke_directo.ps1`)
- **Resultado: 26/26 PASS / 0 FAIL.**
- Seguridad: **8/8** (vicky/socio OK; jenny e intruso → `rol_no_permitido`; `firma_invalida`; ts viejo → `ts_fuera_de_ventana`; ambiente cruzado → `ambiente_incorrecto`; action ajena → `accion_desconocida`).
- Funcionales: **10/10**, cruzando con S8/S9 (período `[2026-07-01, 2026-12-31]`):
  - `total_cobrado = 921200` (solo `sena`+`saldo`), `total = 4` pagos.
  - `por_mes`: julio 670200 · noviembre 251000.
  - `por_medio`: efectivo 300200 · transferencia_bancaria 621000.
  - `otros_movimientos`: extra 8500 (**separado, no sumado** al headline).
  - **Cuadre** (con `limit=200`): `Σ por_medio = Σ por_tipo = Σ filas = total_cobrado`.
  - `por_tipo` solo `sena`/`saldo`; default `{}` hoy → vacío (`total_cobrado=0`) por floor futuro; `periodo_desde<floor` recortado.
- Payload inválido: **7/7** (clave no permitida; `periodo_desde` mal formado; **inversión explícita**; `periodo_hasta` mal formado; `limit` no entero; payload string; payload array).
- META allowlist: **OK**.

## Estado
- **No gateway todavía** (A25 no cableado en `portal-api`; ese es el bloque siguiente).
- **No OPS · no writes · no canónico** (sin DDL, sin funciones nuevas, OPS intacto, schema sin cambios).

## Reglas confirmadas en el bloque
- `total_cobrado` = solo `sena`+`saldo` confirmados (D-9G-03); `otros_movimientos` informativo (no suma, no neto, no cascada, no matriz, no reabre Carril B; D-C-27).
- **Suma sobre `pagos`** (incluye el residuo); `cabana` por LEFT JOIN (null en el residuo).
- Floor `2026-07-01` (D-NEG-02): `periodo_desde` se recorta al floor.
- **`periodo_hasta` híbrido**: omitido → hoy, sin check de inversión (floor futuro → vacío OK); explícito → YMD válido y `>= periodo_desde` tras el clamp, sino `payload_invalido`.
- `filas` **paginada** (`limit`/`offset`): el cuadre `Σ filas = total_cobrado` solo aplica cuando la página trae todo el universo; `Σ por_medio = Σ por_tipo = total_cobrado` vale siempre.
- `payload` no-objeto → `payload_invalido` (C1); IDs `BIGINT` (`id_pago`/`id_reserva`) → número (C2).
- Bucket por mes de `created_at` (criterio Carril B vigente, sin conversión de zona).
