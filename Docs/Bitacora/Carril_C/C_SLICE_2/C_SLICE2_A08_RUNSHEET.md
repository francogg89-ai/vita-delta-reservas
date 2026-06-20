# C_SLICE2 / A08 - RUNSHEET de smokes directos (wrapper)

Wrapper: **portal-a08-crear-bloqueo__TEST** (10 nodos). Reusa el molde de seguridad
validado de A07 (firma HMAC sobre raw body, ts, rol, action binding, actor) y reemplaza
todo el flujo de pago/confirmacion por una sola escritura atomica `crear_bloqueo`.

Decision 8D: **bloqueo total NO se expone** en el portal. `id_cabana` es OBLIGATORIO
(entero positivo); el payload a `crear_bloqueo` es siempre especifico.

---

## Pre-requisitos

- Workflow **ACTIVO** durante toda la bateria (el webhook productivo `/webhook/` requiere
  `active:true`). Se vuelve a `active:false` al final.
- Credencial `vita_supabase_test` en los 2 nodos Postgres (`leer_ambiente`, `PG crear_bloqueo`).
- HMAC real de TEST en `validar_firma_ts_rol` (el mismo de A07).
- Dry-parse ya corrido y verde (`C_SLICE2_A08_dryparse.sql`).

## Variables de entorno (para los .ps1)

```powershell
$env:VITA_HMAC_SECRET_TEST = "<secreto HMAC real de TEST>"
```

> Los .ps1 son ASCII puros (PS 5.1 los lee como CP1252; nada de acentos ni guion largo).
> Los .sql se ejecutan en el SQL Editor de Supabase (UTF-8): seleccionar todo o no
> seleccionar nada para correr el script completo.

---

## Orden de ejecucion

### BLOQUE 1 - Seguridad (sin escritura)
```powershell
pwsh ./C_SLICE2_A08_smoke_seguridad.ps1
```
**Esperado: 15/15 PASS.** Ningun caso escribe (todos rebotan antes del SQL).
Cubre: rol vicky/socio habilitado (payload invalido -> payload_invalido), jenny/basura
-> rol_no_permitido, firma/ts/ambiente/action, reject-unknown, actor fuera de enum,
fecha imposible, fecha_hasta<=desde, motivo invalido, id_cabana 0 y null (obligatorio).

### BLOQUE 2 - Gate residual (pre)
```sql
-- C_SLICE2_A08_gate_residual.sql
```
**Esperado: bloqueos=0, log_cambios=0.** Si hay algo, correr el teardown antes de seguir.

### BLOQUE 3 - Smoke funcional (con escritura)
```powershell
pwsh ./C_SLICE2_A08_smoke_funcional.ps1
```
**Esperado: 4/4 PASS.**
- A B_FELIZ -> ok, id_bloqueo, tipo `cabana_especifica`, id_cabana=1.
- B B_RETRY (= B_FELIZ) -> `conflicto` (bloqueo_solapado), sin duplicar.
- C B_SOLAPA (solapa parcial) -> `conflicto`.
- D B_CABANA99 (cabana inexistente) -> `payload_invalido` (cabana_no_existe; ejercita el
  camino dentro de crear_bloqueo).

### BLOQUE 4 - Verificacion de escrituras
```sql
-- C_SLICE2_A08_verif_writes.sql
```
**Esperado: B_FELIZ=1, B_SOLAPA=0, B_CABANA99=0, TOTAL_NS=1.**
El `TOTAL_NS=1` es la prueba dura de no-duplicacion (el retro-POST de B_FELIZ no creo
una segunda fila).

### BLOQUE 5 - Teardown
```sql
-- C_SLICE2_A08_teardown.sql
```
Borra el namespace `portal_test_a08_%` en `bloqueos` + `log_cambios` (guard anti-OPS:
aborta si el entorno no es TEST). Esperado NOTICE `bloqueos=1 log_cambios>=1`.

### BLOQUE 6 - Gate residual (post)
```sql
-- C_SLICE2_A08_gate_residual.sql
```
**Esperado: 0 y 0.**

### Cierre
- Volver el workflow a **`active:false`**.

---

## Fixtures (source_event determinístico)

| fixture     | cabana | fechas               | motivo        | source_event |
|-------------|--------|----------------------|---------------|--------------|
| B_FELIZ     | 1      | 2027-09-01..09-05    | mantenimiento | portal_test_a08_cab1_2027-09-01_2027-09-05_e94b425e607d |
| B_SOLAPA    | 1      | 2027-09-03..09-07    | mantenimiento | portal_test_a08_cab1_2027-09-03_2027-09-07_6b376e54cabd |
| B_CABANA99  | 99     | 2027-09-10..09-12    | mantenimiento | portal_test_a08_cab99_2027-09-10_2027-09-12_e31714741c8b |

Tras cerrar los smokes directos: extension del gateway (`payloadCrearBloqueo` + entrada
de CATALOG, reusa toda la infra A07) y sus smokes. Recien despues, A10.
