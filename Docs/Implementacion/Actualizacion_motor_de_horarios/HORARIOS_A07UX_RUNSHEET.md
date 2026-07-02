# Runsheet - Mini-bloque UX A07: `override_hora_invalido` -> `payload_invalido`

**Alcance:** SOLO A07, SOLO TEST. **Estado:** NADA aplicado; se ejecuta cuando lo autorices.
**Identificador del smoke:** motivo `smoke_a07_ovr_e2268a33` / huesped `SMOKE_A07_OVR` / fechas `2027-06-15`..`2027-06-17`.
**No se toca:** gateway, frontend, SQL de negocio, canonico, OPS, A08, `obtener_disponibilidad_rango`. Sin `D-*`/`L-*`.

## Artefactos
1. `portal-a07-crear-reserva__TEMPLATE.json` - template repo con el unico delta (paridad repo<->live).
2. `HORARIOS_A07UX_SETUP_TEST.sql` - fixture (setup).
3. `HORARIOS_A07UX_TEARDOWN_TEST.sql` - limpieza (teardown).
4. `HORARIOS_A07UX_POSTCHECK_TEST.sql` - verificacion final (read-only).
5. `HORARIOS_A07UX_smoke_e2e_TEST.ps1` - smoke E2E firmado.

> Los 3 SQL estan SEPARADOS a proposito: cada uno se corre **completo, con nada seleccionado**, sin riesgo de que el setup se auto-borre antes del smoke.

## Paso 0 - Gate ambiente (manual)
`SELECT valor FROM configuracion_general WHERE clave='ambiente';` -> debe ser **`test`**. Si no, PARAR. (SETUP y TEARDOWN ya traen el gate embebido y abortan si no es test.)

## Paso 1 - Aplicar el delta al wrapper (edicion directa, NO re-import)
En n8n TEST, workflow `portal-a07-crear-reserva__TEST`, nodo **`router1_crear`**: en el array `payloadInv`, agregar `'override_hora_invalido'` despues de `'fecha_in_pasada'`. Guardar el workflow. **No re-importar** el JSON completo (evita re-inyectar HMAC/credenciales).
Repo: reemplazar `portal-a07-crear-reserva__TEMPLATE.json` por el artefacto (paridad repo<->live). Commit aparte.

## Paso 2 - SETUP del fixture
Correr COMPLETO (nada seleccionado) `HORARIOS_A07UX_SETUP_TEST.sql`.
Deja el override corrupto (`hora_checkin='25:99'`) en una cabana activa para `2027-06-15`.
**Esperado:** una fila con `estado='SETUP_OK'`. **Anotar el `id_cabana`** que devuelve.

## Paso 3 - Smoke E2E
En `HORARIOS_A07UX_smoke_e2e_TEST.ps1` setear `$Secret` (VITA_HMAC_SECRET de A07 TEST) y `$IdCabana` (el del Paso 2). Correr.
**Esperado (PASS):** HTTP 200, `ok=false`, `error.code='payload_invalido'`, `error.message` contiene `override_hora_invalido`.
El HARD corta en 3.5: no consume secuencias, no crea pre-reserva ni huesped.

## Paso 4 - TEARDOWN (SIEMPRE, pase o falle el smoke)
Correr COMPLETO (nada seleccionado) `HORARIOS_A07UX_TEARDOWN_TEST.sql`.
**Esperado:** una fila con `estado='TEARDOWN_OK'` y `overrides_restantes=0`.
> **REGLA DURA:** aunque el smoke falle o tire error HTTP, corre el TEARDOWN igual. **No puede quedar un override corrupto vivo** (mientras exista, cualquier reserva real con `fecha_in`/`fecha_out` = `2027-06-15`/`2027-06-17` en esa cabana rebotaria). El smoke, en fallo/error, imprime el recordatorio con el nombre del archivo.

## Paso 5 - POSTCHECK (read-only)
Correr COMPLETO (nada seleccionado) `HORARIOS_A07UX_POSTCHECK_TEST.sql`.
**Esperado:** una fila con `estado='POSTCHECK_OK'` y las 3 columnas en **0**:
- `overrides_smoke = 0` (fixture borrado);
- `prereservas_smoke = 0` (el HARD corta antes del INSERT);
- `huespedes_smoke = 0` (el HARD corta antes de `upsert_huesped`).

Si `estado='POSTCHECK_FAIL'`: hallazgo a investigar. El teardown de overrides ya se corrio; pre_reservas/huespedes se reportan, no se borran automaticamente.

---

## Diff minimo
- **Template/nodo:** un unico string `'override_hora_invalido'` agregado al array `payloadInv` de `router1_crear`. Probado por reverse-replace (delta byte a byte = +25 bytes, exactamente `,'override_hora_invalido'`), JSON valido, `node --check` EXIT 0. Cero cambios en otros nodos, conexiones, credenciales o HMAC.
- **Efecto:** el HARD del resolver (`error='override_hora_invalido'`) deja de caer al `else` (`error_interno`) y se mapea a `payload_invalido` con message `datos de reserva rechazados: override_hora_invalido`, `detail:null`. Gateway y frontend sin cambios (mismo code ya allowlisted y probado por el guard B3).

## Rollback
- **Wrapper:** abrir `router1_crear` en n8n TEST, **quitar** `,'override_hora_invalido'` del array `payloadInv`, guardar. (O re-importar el `__TEMPLATE.json` previo.) Vuelve a `error_interno` para ese codigo. Trivial, sin efectos colaterales.
- **Fixture:** `HORARIOS_A07UX_TEARDOWN_TEST.sql` (idempotente, `DELETE ... WHERE motivo='smoke_a07_ovr_e2268a33'`).
