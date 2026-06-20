# C_SLICE2 / A08 - RUNSHEET del gateway (portal-api -> wrapper A08)

Gateway canonico nuevo: **C_SLICE2_A08_portal-api_index.ts** (608 lineas). Extiende el de
A07 con la constante `ENUM_MOTIVO_GW`, el validador espejo `payloadCrearBloqueo` y la
entrada de CATALOG `'bloqueo.crear_manual'`. Reusa toda la infra A07 (firma, JWT,
`buildSignedEnvelope` con actor, `dispatchN8n` con `isWrite->estado_incierto`,
`actorCoherente`). No agrega codigos de error nuevos.

El `actor` se inyecta server-side desde `portal_usuarios.nombre` y el wrapper A08 lo usa
como `creado_por`. `id_cabana` es OBLIGATORIO (bloqueo total no se expone, 8D).

---

## Pre-requisitos
- Wrapper A08 ACTIVO en n8n (el gateway despacha al webhook firmado).
- Env vars: `VITA_SUPABASE_URL_TEST`, `VITA_SUPABASE_ANON_TEST`,
  `VITA_PW_VICKY`, `VITA_PW_FRANCO`, `VITA_PW_JENNY`.

## Paso 0 - Deploy del gateway
Desplegar **C_SLICE2_A08_portal-api_index.ts** como la Edge Function `portal-api` en TEST
(reemplaza el index actual; trae A05 + A07 + A08 y las lecturas de Slice 1).

## Orden de ejecucion

### Precheck auth
```powershell
powershell -ExecutionPolicy Bypass -File .\C_SLICE2_A08_GW_precheck_auth.ps1
```
Esperado: vicky/franco/jenny con JWT; `bloqueo.crear_manual` habilitado para vicky/socio,
NO para jenny.

### Gate residual (pre)
```sql
-- C_SLICE2_A08_gate_residual.sql  (el del bloque directo: namespace portal_test_a08_%)
```
Esperado: bloqueos=0, log_cambios=0.

### Smoke gateway
```powershell
powershell -ExecutionPolicy Bypass -File .\C_SLICE2_A08_GW_smoke.ps1
```
Esperado **7/7 PASS**: a vicky feliz, b socio/franco feliz, c jenny->rol_no_permitido,
d sin JWT->no_autorizado, e payload invalido->payload_invalido, f creado_por en payload
(spoof)->payload_invalido (reject-unknown), g action inexistente->accion_desconocida.

### Verificacion (actor inyectado)
```sql
-- C_SLICE2_A08_GW_verif.sql
```
Esperado: GW_VICKY bloqueos=1 creado_por=vicky ; GW_FRANCO bloqueos=1 creado_por=franco.
Prueba que `creado_por` salio del JWT (server-side), no del payload.

### Teardown + gate (post)
```sql
-- C_SLICE2_A08_teardown.sql       (namespace portal_test_a08_% cubre cab2/cab3 del GW)
-- C_SLICE2_A08_gate_residual.sql  -> 0 y 0
```
Luego volver el wrapper A08 a `active:false`.

---

## Fixtures gateway (source_event determinístico)

| caso      | cabana | fechas             | actor (JWT) | source_event |
|-----------|--------|--------------------|-------------|--------------|
| GW_VICKY  | 2      | 2027-10-01..10-03  | vicky       | portal_test_a08_cab2_2027-10-01_2027-10-03_cf49bb4ec368 |
| GW_FRANCO | 3      | 2027-10-01..10-03  | franco      | portal_test_a08_cab3_2027-10-01_2027-10-03_f3658020d1e4 |

Con el gateway A08 en verde se cierra la parte construible de A08. Siguiente: A10. Recien
con A07/A08/A10 cerrados se genera `C_SLICE2_CIERRE.md` y se propagan los satelites.
