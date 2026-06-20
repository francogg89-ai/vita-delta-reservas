# C_SLICE2 / A07 GATEWAY — RUNSHEET de smoke vía gateway (orden estricto)

End-to-end por el gateway `portal-api` → wrapper A07. **TEST only.** El precheck ya pasó en verde (los 3 JWTs + `sesion.contexto`).

## Pre-condiciones
- `index.ts` del gateway (`C_SLICE2_A07_portal-api_index.ts`) **desplegado** en la Edge Function `portal-api` de TEST.
- Workflow `portal-a07-crear-reserva__TEST` **ACTIVO** (`active:true`); al final se vuelve a `active:false`.
- Env vars en la consola de los `.ps1`: `VITA_SUPABASE_URL_TEST`, `VITA_SUPABASE_ANON_TEST`, `VITA_PW_VICKY`, `VITA_PW_FRANCO`, `VITA_PW_JENNY`.
- Reservas directas de A07 ya limpiadas (gate residual en 0).

## Orden

| # | Paso | Archivo | Escribe | Esperado |
|---|------|---------|:---:|----------|
| 0 | Precheck Auth/JWT | `C_SLICE2_A07_GW_precheck_auth.ps1` | no | 3 usuarios verdes (ya hecho) |
| 1 | **Gate residual** | `C_SLICE2_A07_gate_residual.sql` | no | 5 filas en 0 |
| 2 | **Smoke vía gateway** | `C_SLICE2_A07_GW_smoke.ps1` | sí (a/b) | **7/7 PASS** |
| 3 | **Verif. gateway** | `C_SLICE2_A07_GW_verif.sql` | no | `GW_VICKY 1/1 vicky/vicky` · `GW_SOCIO 1/1 franco/franco` |
| 4 | **Teardown FK-safe** | `C_SLICE2_A07_teardown.sql` | borra | `NOTICE` con filas borradas (incluye los GW por namespace) |
| 5 | **Gate residual** | `C_SLICE2_A07_gate_residual.sql` | no | 5 filas en 0 |
| 6 | Post | (desactivá el workflow: `active:false`) | — | — |

## Qué prueba cada caso del smoke (paso 2)
- **a/b** vicky y socio(franco) → camino feliz: el gateway valida payload, inyecta `actor`, firma y despacha; el wrapper crea la reserva. El `actor` NO lo manda el smoke — lo pone el gateway desde el JWT.
- **c** jenny → `rol_no_permitido` (allowlist del gateway, antes de firmar).
- **d** sin JWT → `no_autorizado`.
- **e** payload inválido (seña>total) → `payload_invalido` (gateway, antes de firmar).
- **f** `actor` dentro del payload → `payload_invalido` (reject-unknown): demuestra que el frontend **no** puede inyectar el actor.
- **g** action inexistente → `accion_desconocida`.

## Por qué el verif (paso 3) importa
El envelope sólo devuelve `id_reserva`/`idempotent_match`. La verificación a nivel base confirma lo que el envelope no muestra: **el actor inyectado** (`validado_por` de la seña y `created_by` de la reserva) coincide con la identidad del JWT (`vicky`/`franco`), no con nada del payload. Y que no hubo duplicación (`1/1`).

## Notas
- Fixtures GW: huéspedes `PORTAL TEST A07 GW *`, teléfonos `+549000000080X`, fechas 2027-07. El teardown directo los cubre (`source_event LIKE 'portal_test_a07_%'`, huésped `LIKE 'PORTAL TEST A07%'`).
- Repetible: si re-corrés el smoke sin teardown, a/b darán `idempotent_match:true` (igual `ok:true`, sin duplicar). El gate residual antes del paso 2 asegura empezar limpio.
- Sin auto-retry en el gateway: ante dispatch no confiable de una escritura, el gateway responde `estado_incierto` (no `error_entorno`).

## Límite de verificación (honesto)
Los `.ps1` no los pude ejecutar desde mi lado (sin `pwsh`/red/JWT); ASCII puro verificado y lógica del gateway testeada en Node. Las queries son SELECT/DELETE simples con guard anti-OPS. La validación real es al correrlos.
