# C_SLICE3A_A24_GW_CIERRE.md

**Carril C / Portal Operativo Interno — Slice 3a · Bloque gateway A24. CERRADO EN VERDE.**
Fecha de cierre: 2026-06-20.

## Alcance
- Acción de **lectura** `historico.reservas` cableada en el gateway `portal-api` (Edge Function).
- Wrapper ruteado: `portal-a24-historico-reservas` (TEST). **Sin `injectActor`, sin `isWrite`.**
- **TEST exclusivamente** (`bdskhhbmcksskkzqkcdp`).

## Cambios en el gateway (diff quirúrgico contra `C_SLICE2_A10_portal-api_index.ts`)
- **0 líneas eliminadas, 79 agregadas** (pura inserción). Solo dos bloques:
  1. Validador `payloadHistoricoReservas` (+ consts `FLOOR_A24_GW`, `ENUM_ESTADO_RESERVA_GW`) **antes del `CATALOG`** (TDZ, L-C-11). Reusa `isYMD_GW`/`MAXLEN_GW`. Devuelve el payload **normalizado/whitelisteado** (`{ fecha_desde, fecha_hasta, id_cabana, estado, texto, limit, offset }`), que es lo que se firma y se manda (`v.value`); el wrapper revalida idempotentemente (2da defensa, D-C-39).
  2. Entrada CATALOG `'historico.reservas'` → `roles:['vicky','socio']`, `webhook:'portal-a24-historico-reservas'`, `validate: payloadHistoricoReservas`. **CATALOG 9 → 10.**
- **No se tocó:** `dispatchN8n`, `buildSignedEnvelope`, `actorCoherente`, CORS, `CODIGOS_ERROR_PERMITIDOS` (allowlist), `resolveEnv`/preflight, HMAC, ni las 9 entradas previas.

## Evidencia
- **Smoke directo** (`C_SLICE3A_A24_smoke_directo.ps1`): **26/26 PASS** (8 seguridad + 10 funcionales + 7 payload + META).
- **Smoke gateway** (`C_SLICE3A_A24_GW_smoke.ps1`, por JWT): **23/23 PASS** (5 seguridad + 10 funcionales + 7 payload + META).
  - Seguridad gateway: vicky/socio OK; jenny → `rol_no_permitido` (rebota en el gateway antes de firmar); sin JWT → `no_autorizado`; action inexistente → `accion_desconocida`.
  - Sin filtros: `total=7`, `filas=7` (universo floored).
  - Códigos vistos: `accion_desconocida`, `no_autorizado`, `payload_invalido`, `rol_no_permitido` (todos en la allowlist).
- Verificación previa: esbuild OK · `payloadHistoricoReservas` pasa `tsc --strict` · validador ejecutado con 17 casos → 17 PASS (idéntico al wrapper).

## Estado
- **A24 (`historico.reservas`) COMPLETO**: directo + gateway, ambos en verde.
- **No OPS · no writes · no canónico** (sin DDL, sin funciones nuevas, OPS intacto, schema sin cambios).
- Las 9 acciones previas del CATALOG quedan intactas (garantizado por el diff de 0 líneas eliminadas).

## Próximo
- **A25 `ingresos.cobrados_periodo`** con la misma disciplina: primero wrapper directo + smoke directo, sin gateway hasta cerrar el directo. (Una decisión de contrato abierta a confirmar antes de construir: ver kickoff.)
