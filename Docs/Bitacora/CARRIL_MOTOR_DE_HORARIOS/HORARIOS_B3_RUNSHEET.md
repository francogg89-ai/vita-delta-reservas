# HORARIOS_B3 — Runsheet (UX wrappers A07/A08, SOLO TEST)

**Objetivo único:** que `fecha_in_pasada` (A07) y `rango_pasado` (A08) lleguen al frontend como `payload_invalido` con mensaje específico, en vez del genérico `error_interno`.
**Entorno:** TEST. **NO OPS.**
**Artefactos repo:** `portal-a07-crear-reserva__TEMPLATE.json`, `portal-a08-crear-bloqueo__TEMPLATE.json` (actualizados).
**Artefacto smoke:** `HORARIOS_B3_smoke_e2e_TEST.ps1`.
**Ejecutor:** Franco. Claude no escribe en n8n ni en ninguna DB.

---

## 1. Alcance

Un string agregado al array `payloadInv` de un nodo por wrapper. Nada más. **No se toca:** SQL, `fecha_hoy_ar`/`crear_prereserva`/`crear_bloqueo`, gateway `portal-api`, frontend, calendario, override, `overrides_operativos`, canónico, OPS. El `portal-a07-crear-reserva__OPS.json` (promoción a OPS) queda **explícitamente fuera de alcance**.

## 2. Diff conceptual

**A07 — nodo `router1_crear`**, array `payloadInv`:
```diff
- ...'hora_fuera_de_rango','payload_invalido']
+ ...'hora_fuera_de_rango','payload_invalido','fecha_in_pasada']
```

**A08 — nodo `router_bloqueo`**, array `payloadInv`:
```diff
- ['payload_invalido','fechas_invalidas','motivo_invalido','cabana_no_existe']
+ ['payload_invalido','fechas_invalidas','motivo_invalido','cabana_no_existe','rango_pasado']
```

Como `jsCode` se guarda en el JSON como un único string, el diff a nivel línea muestra toda la línea del `jsCode`, pero el delta a nivel carácter es solo `,'fecha_in_pasada'` / `,'rango_pasado'`. El builder lo probó por identidad de reverse-replace (al revertir el string agregado se obtiene el archivo original byte a byte).

## 3. Pasos de edición LIVE en n8n UI

Edición directa del nodo (NO re-importar el workflow: re-importar forzaría re-inyectar el secreto HMAC y re-cablear credenciales).

**A07 — workflow `portal-a07-crear-reserva__TEST`:**
1. Abrir el workflow en n8n.
2. Doble clic en el nodo **`router1_crear`** (Code node).
3. Ubicar `const payloadInv = [ ... 'hora_fuera_de_rango','payload_invalido'];`.
4. Agregar `,'fecha_in_pasada'` justo antes del `]` → queda `...'payload_invalido','fecha_in_pasada'];`.
5. Cerrar el editor del nodo. **Guardar** el workflow (queda activo; no se desactiva).

**A08 — workflow `portal-a08-crear-bloqueo__TEST`:**
1. Abrir el workflow.
2. Doble clic en el nodo **`router_bloqueo`** (Code node).
3. Ubicar `const payloadInv = ['payload_invalido','fechas_invalidas','motivo_invalido','cabana_no_existe'];`.
4. Agregar `,'rango_pasado'` justo antes del `]` → queda `...'cabana_no_existe','rango_pasado'];`.
5. Cerrar el editor. **Guardar** el workflow.

## 4. Smokes E2E sin consumo (payloads válidos salvo el defecto)

El smoke `HORARIOS_B3_smoke_e2e_TEST.ps1` corre dos casos contra el gateway con JWT de vicky. **Payload válido en todo salvo la fecha**, para que ninguna validación previa (gateway o wrapper) robe el caso: el error que dispara es el del guard SQL.

- **A07:** `id_cabana` real (default 4), `fecha_in` pasada (hoy-10), `fecha_out>fecha_in`, `personas=2`, `monto_total/monto_sena` válidos, `canal_pago_esperado='efectivo'`, `medio_pago='efectivo'`, huésped con teléfono. **Esperado:** `payload_invalido` con mensaje que incluye `fecha_in_pasada`.
- **A08:** `id_cabana` real (default 4, no NULL), rango completamente pasado (hoy-10 → hoy-8), `motivo='mantenimiento'` válido. El actor/source_event los inyecta el gateway desde el JWT (NO van en el payload; el gateway los rebotaría). **Esperado:** `payload_invalido` con mensaje que incluye `rango_pasado`.

**Sin consumo:** el guard SQL corta antes de cualquier `INSERT`/`nextval` → no crea filas ni consume secuencias. No hace falta cleanup.

Requisitos: `VITA_SUPABASE_URL_TEST`, `VITA_SUPABASE_ANON_TEST`, `VITA_PW_VICKY`. Workflows A07/A08 activos y con el cambio guardado. Uso:
```
powershell -ExecutionPolicy Bypass -File .\HORARIOS_B3_smoke_e2e_TEST.ps1 -IdCabana 4
```
(`id_cabana=4` es una cabaña real de TEST — la usan los fixtures del smoke A07 vigente. Si preferís otra, pasá `-IdCabana <real>`. Para obtener una real read-only: `SELECT id_cabana, nombre FROM cabanas WHERE activa ORDER BY id_cabana;`.)

## 5. Rollback

Por wrapper: abrir el nodo y **quitar** el string agregado del array `payloadInv` → guardar. (O re-importar el `__TEMPLATE.json` previo.) Trivial, sin efectos colaterales. El comportamiento vuelve a `error_interno` para esos códigos.

## 6. Evidencia esperada (separada repo vs live, Ajuste 2)

### 6.1 Repo
- Diff de `portal-a07-crear-reserva__TEMPLATE.json`: única diferencia, `+,'fecha_in_pasada'` en `payloadInv` de `router1_crear`.
- Diff de `portal-a08-crear-bloqueo__TEMPLATE.json`: única diferencia, `+,'rango_pasado'` en `payloadInv` de `router_bloqueo`.
- Validación: JSON válido + `node --check` del `jsCode` EXIT 0 (ya verificado en el build).

### 6.2 Live n8n TEST
- Pasos de edición de `router1_crear` (A07) y `router_bloqueo` (A08) ejecutados y workflows guardados (sección 3).
- Salida del smoke E2E firmado tras guardar:
  - `[PASS] A07 fecha_in pasada -> code=payload_invalido msg='datos de reserva rechazados: fecha_in_pasada'`
  - `[PASS] A08 rango pasado    -> code=payload_invalido msg='datos de bloqueo rechazados: rango_pasado'`
  - `2/2 PASS`
- **Resultado esperado vs obtenido:** pegar la salida real del smoke. PASS si ambos casos dan `payload_invalido` con el mensaje específico (no `error_interno`).

**Paridad:** el repo (templates) y el live (nodos) quedan con el mismo cambio — el array `payloadInv` con el código nuevo en ambos lados.

## 7. Confirmación de alcance no tocado

- **OPS:** no se toca (ni el `__OPS.json` ni nada en OPS).
- **Canónico:** no se modifica.
- **SQL:** no se toca (`fecha_hoy_ar`, `crear_prereserva`, `crear_bloqueo` intactos; sus fingerprints de B2 no cambian).
- **Gateway `portal-api`:** no se toca (`payload_invalido` ya allowlisted y con mensaje conservado).
- **Frontend / calendario:** no se tocan.
- **Override manual / `overrides_operativos`:** no se tocan.
- Sin acuñar `D-*`/`L-*`.
