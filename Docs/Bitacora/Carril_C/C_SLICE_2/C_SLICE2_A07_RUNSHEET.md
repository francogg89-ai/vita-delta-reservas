# C_SLICE2 / A07 — RUNSHEET de smokes directos (orden estricto)

Wrapper `portal-a07-crear-reserva__TEST`, **TEST**, **sin gateway todavía**.
Ejecutá en este orden y **no avances si un paso no da el resultado esperado**.

## Pre-condiciones (una vez)
- **Activá el workflow** en n8n (`active:true`). El webhook productivo `/webhook/<path>` requiere `active:true`; el `webhook-test` (un disparo por click) no sirve para una batería. Al final (paso 10) se vuelve a `active:false`.
- Exportá el secreto en la consola donde corras los `.ps1` (no queda en disco) — el mismo que pusiste en el nodo `validar_firma_ts_rol`:

  ```powershell
  $env:VITA_HMAC_SECRET_TEST = "<secreto real de TEST>"
  ```
- PowerShell 7+ (el smoke de concurrencia usa `ForEach-Object -Parallel`).

## Orden

| # | Paso | Archivo | Escribe | Esperado |
|---|------|---------|:---:|----------|
| 1 | **Bloque 1 — Seguridad** | `C_SLICE2_A07_smoke_seguridad.ps1` | no | **12/12 PASS** (vicky/socio→`payload_invalido`; jenny/basura→`rol_no_permitido`; firma/ts/ambiente/action/actor/fecha/hora rebotan) |
| 2 | **Bloque 2 — Gate residual** | `C_SLICE2_A07_gate_residual.sql` | no | **5 filas en 0**. Si hay residual, corré el teardown (paso 9) y repetí. |
| 3 | **Setup Caso 2** (retry parcial) | `C_SLICE2_A07_setup_caso2.sql` | sí | `prereserva_activa=1, sena_confirmada=1, reservas=0` |
| 4 | **Bloque 3 — Funcional** | `C_SLICE2_A07_smoke_funcional.ps1` | sí | **5/5 PASS** (A feliz; B Caso1 `idempotent_match:true` mismo `id_reserva`; C `conflicto`; D `payload_invalido`; E Caso2 resume) |
| 5 | **Verif. escrituras** | `C_SLICE2_A07_verif_writes.sql` | no | `FELIZ 1/1/1`, `PARCIAL 1/1/1`, `NODISP 0/0/0`, `CAPAC 0/0/0`, `CONCUR 0/0/0` |
| 6 | **Bloque 4 — Concurrencia** | `C_SLICE2_A07_smoke_concurrencia.ps1` | sí | todos `ok:true`, **1 `id_reserva` distinto**, 1 creador |
| 7 | **Verif. concurrencia** | `C_SLICE2_A07_verif_writes.sql` | no | **`CONCUR 1/1/1`** (el resto igual que paso 5) |
| 8 | — | (revisión: ningún `reservas`/`pagos_sena` debe ser >1) | — | sin duplicados |
| 9 | **Bloque 5 — Teardown FK-safe** | `C_SLICE2_A07_teardown.sql` | borra | `NOTICE` con filas borradas por tabla |
| 10 | **Bloque 6 — Verif. 0 residual** | `C_SLICE2_A07_gate_residual.sql` | no | **5 filas en 0** |
| 11 | Post | (desactivá el workflow: `active:false`) | — | — |

## Notas
- Los casos `NODISP`/`CAPAC` rebotan sin crear reserva/prereserva, pero `crear_prereserva` corre `upsert_huesped` **antes** de validar disponibilidad/capacidad, así que dejan un huésped centinela. El teardown los borra por `nombre LIKE 'PORTAL TEST A07%'`.
- El **Caso 2** (E) sólo prueba el "resume sin duplicar seña" si el **setup (paso 3)** corrió antes: con el estado parcial presente, el POST reusa la prereserva (idempotent en PG-1) y la seña (PG-2, `n=1,n_conf=1`) y sólo confirma. Sin setup, haría el camino completo (mismo envelope, distinto camino interno).
- `idempotent_match` es `false` cuando la reserva se crea en esta corrida (incluido el resume del Caso 2, porque la reserva se crea recién al confirmar) y `true` cuando ya existía (Caso 1 / recheck de concurrencia).
- Fixtures: fechas **2027**, huéspedes `PORTAL TEST A07 *`, teléfonos `+549000000070X`. `idem` determinístico por fixture (ver `verif_writes.sql`).

## Límite de verificación (honesto)
Los `.ps1` no los pude ejecutar desde mi lado (sin `pwsh`, sin secreto, sin red a n8n); los revisé a mano. Las queries de escritura ya pasaron el dry-parse; el teardown/verificación son SELECT/DELETE simples. La validación real es al correrlos.
