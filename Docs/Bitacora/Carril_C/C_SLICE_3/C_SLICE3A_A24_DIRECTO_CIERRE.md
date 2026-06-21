# C_SLICE3A_A24_DIRECTO_CIERRE.md

**Carril C / Portal Operativo Interno — Slice 3a · Bloque A24 directo. CERRADO EN VERDE.**
Fecha de cierre: 2026-06-20.

## Alcance
- Acción nueva de **lectura**: `historico.reservas` (buscador operativo de reservas).
- Wrapper n8n: **`portal-a24-historico-reservas`** (firmado HMAC, camino directo sin gateway).
- **TEST exclusivamente** (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`).

## Evidencia (smoke directo `C_SLICE3A_A24_smoke_directo.ps1`)
- **Resultado: 26/26 PASS / 0 FAIL.**
- Seguridad: **8/8** (vicky/socio OK; jenny e intruso → `rol_no_permitido`; `firma_invalida`; ts viejo → `ts_fuera_de_ventana`; ambiente cruzado → `ambiente_incorrecto`; action ajena → `accion_desconocida`).
- Funcionales: **10/10** (sin filtros `total=7`/`filas=7` cuadra con el universo floored; `fecha_desde`; floor-regression 0 filas `< 2026-07-01`; `id_cabana`; `estado`; `texto`; paginación).
- Payload inválido: **7/7** (clave no permitida; fecha mal formada; estado fuera de enum; `id_cabana` decimal; `fecha_hasta < fecha_desde`; payload string; payload array).
- META allowlist: **OK** (todos los `error.code` dentro de la allowlist del gateway).

## Estado
- **No gateway todavía** (A24 no cableado en `portal-api`; ese es el bloque siguiente).
- **No OPS · no writes · no canónico** (sin DDL, sin funciones nuevas, OPS intacto, schema sin cambios).

## Reglas confirmadas en el bloque
- `saldo_real` computado por CTE (`monto_total − Σ sena/saldo confirmados`), CTE desde `reservas.id_pre_reserva → MIN(id_reserva)` (D-C-49); la columna stored `reservas.monto_saldo` NO se usa.
- Floor inferior duro `2026-07-01` (D-C-11/20): `fecha_desde` anterior se recorta, no se rechaza.
- `payload` no-objeto → `payload_invalido` (sin coerción silenciosa a `{}`).
- IDs `BIGINT` (`id_reserva`, `id_cabana`) normalizados a número en el contrato.
- Privacidad (D-C-03): huésped nombre/teléfono/email; sin `dni` ni `notas_internas`.
