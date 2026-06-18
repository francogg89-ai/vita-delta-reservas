# RUNSHEET — Slice 1 / Bloque 6 (wrapper de A05 `reserva.detalle`)

Carril C / Portal Operativo Interno. **Entorno: TEST únicamente.** No toca OPS ni el schema canónico.
Este bloque construye y smoke-ea el wrapper n8n **directo** (sin gateway). El cableado en `portal-api`
(CATALOG + smoke vía gateway) es el bloque siguiente.

Artefactos del bloque:
- `portal-a05-detalle__TEMPLATE.json` — workflow n8n (sanitizado: secreto y credencial con placeholder, `active:false`).
- `C_SLICE1_B6_smoke_a05_directo.ps1` — smoke directo (14 casos).

---

## 0) Decisiones que este bloque materializa (registrar al CIERRE del slice, no ahora)
- **D-C-42** — action congelada `reserva.detalle`. El key del CATALOG y `EXPECTED_ACTION` del wrapper deben coincidir exacto.
- **D-C-43** — contrato JSON `data:{reserva, pagos}`; montos **numéricos crudos** (el frontend formatea es-AR y renderiza como **texto**, no `innerHTML`).
- **D-C-44** — A05 lee **join directo** (`reservas JOIN cabanas JOIN huespedes` + LATERAL de `pagos`), NO `vista_calendario`, para cubrir reservas completadas/canceladas/fuera de horizonte.
- **Reafirma D-C-40** — `saldo_real` se recalcula en SQL con pagos **confirmados** (`tipo IN ('sena','saldo')`, `monto_recibido`); `saldo_real = monto_total - total_pagado_confirmado`. No se confía en `reservas.monto_saldo` (se expone aparte como `monto_saldo_registrado` para comparar).

---

## 1) Importar el wrapper en n8n (TEST)
1. n8n Cloud → **Import from File** → `portal-a05-detalle__TEMPLATE.json`.
2. Verificá que el Webhook quedó con **path** `portal-a05-detalle` y **Raw Body = ON** (L-C-05; ya viene seteado en el template).

## 2) Credencial Postgres TEST (3 nodos)
Los tres nodos Postgres vienen con placeholder `REEMPLAZAR_POR_CRED_TEST`. Asigná la credencial **vita_supabase_test** en:
- `leer_ambiente`
- `PG: leer reserva`
- `PG: leer pagos`

> Los tres llevan `onError: continueRegularOutput` + `alwaysOutputData` (un error de query degrada a `error_interno`/`ambiente_incorrecto` limpio, no cuelga el workflow). `PG: leer reserva` y `PG: leer pagos` además `executeOnce` y están parametrizados por `$1` vía `options.queryReplacement = {{ $('validar_firma_ts_rol').first().json.id_reserva }}`.

## 3) Secreto HMAC — Modo B (n8n Cloud sin Variables)
En el nodo **`validar_firma_ts_rol`**, reemplazá el placeholder `__PEGAR_SECRETO_O_USAR_VARIABLE__` por el **VITA_HMAC_SECRET real** (el mismo que usan A03/A04 en TEST).
- El assert por prefijo (`SECRET.startsWith('__PEGAR_')`) aborta si te lo olvidás (L-C-10).
- **No** vuelvas a commitear el template con el secreto pegado: el repo queda con el placeholder.

## 4) Activar el workflow
Activá `portal-a05-detalle` (toggle **Active**) para que responda en la URL de producción
`/webhook/portal-a05-detalle` (la que usa el smoke).

---

## 5) Obtener los IDs para el smoke (queries read-only en Supabase TEST)

**Query 1 — elegí un `id_reserva` real:**
```sql
SELECT r.id_reserva, r.estado, r.fecha_checkin, r.fecha_checkout, c.nombre AS cabana,
       h.nombre, h.apellido
FROM reservas r
JOIN cabanas c   ON c.id_cabana  = r.id_cabana
JOIN huespedes h ON h.id_huesped = r.id_huesped
ORDER BY r.id_reserva DESC
LIMIT 10;
```
Elegí uno (idealmente uno con pagos para ver `pagos[]` y `saldo_real` poblados).

**Query 2 — calculá un `id_reserva` garantizado inexistente:**
```sql
SELECT COALESCE(MAX(id_reserva), 0) + 1000000 AS id_reserva_inexistente
FROM reservas;
```

## 6) Completar y correr el smoke
En `C_SLICE1_B6_smoke_a05_directo.ps1`, sección CONFIG:
- `$Secret` = el mismo VITA_HMAC_SECRET pegado en el nodo.
- `$IdReservaOk` = el id de la Query 1.
- `$IdReservaInexistente` = el valor de la Query 2.

Corré el script. (El smoke aborta si falta el secreto o si los IDs quedan en 0.)

---

## 7) Criterio de aceptación (14/14)

| # | Caso | Esperado |
|---|------|----------|
| 1 | vicky + id válido | `ok:true`, `id_reserva=<ok>`, `pagos>=0`, `saldo_real` numérico |
| 2 | socio + id válido | `ok:true`, `id_reserva=<ok>` |
| 3 | jenny + id válido | `ok:false`, `rol_no_permitido` |
| 4 | intruso + id válido | `ok:false`, `rol_no_permitido` |
| 5 | firma inválida | `ok:false`, `firma_invalida` |
| 6 | ts viejo (-10min) | `ok:false`, `ts_fuera_de_ventana` |
| 7 | ambiente cruzado (ops→test) | `ok:false`, `ambiente_incorrecto` (detail esperado=ops real=test) |
| 8 | action ajena (`calendario.operativo`) | `ok:false`, `accion_desconocida` |
| 9 | id inexistente | `ok:false`, `no_encontrado` |
| 10 | payload `{}` (id ausente) | `ok:false`, `payload_invalido` |
| 11 | id_reserva string (`"42"`) | `ok:false`, `payload_invalido` |
| 12 | id_reserva negativo (-5) | `ok:false`, `payload_invalido` |
| 13 | id_reserva decimal (4.5) | `ok:false`, `payload_invalido` |
| 14 | id_reserva no-safe (1e20) | `ok:false`, `payload_invalido` |

Chequeo extra sobre el caso 1: en `data.reserva` deben venir `saldo_real`, `total_pagado_confirmado` y `monto_saldo_registrado`; `huesped` con `nombre/telefono/email` (sin `dni` ni notas del huésped); y `notas`/`notas_reserva` como campos de la reserva.

---

## 8) Próximo bloque (no ahora)
Con los 14/14 verdes: **cablear A05 en el gateway** (`portal-api`) — una línea en el CATALOG
```
'reserva.detalle': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a05-detalle', validate: payloadIdReserva },
```
\+ deploy por Dashboard (verify_jwt OFF, L-C-06) + **smoke vía gateway** (incluye los 5 casos de payload inválido rechazados **en el gateway antes de firmar**, jenny→`rol_no_permitido`, vicky/socio→`ok:true`, id inexistente→`no_encontrado`, sin JWT→`no_autorizado`).
