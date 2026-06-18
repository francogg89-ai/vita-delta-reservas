# RUNSHEET — Slice 1 / Bloque 10 (wrapper de A12 `cobranza.saldos`)

Carril C / Portal Operativo Interno. **Entorno: TEST únicamente.** No toca OPS ni el schema canónico.
Este bloque construye y smoke-ea el wrapper n8n **directo** (sin gateway). El cableado en `portal-api`
(CATALOG + smoke vía gateway) es el bloque siguiente (B11).

Artefactos del bloque:
- `portal-a12-saldos__TEMPLATE.json` — workflow n8n (sanitizado: secreto y credencial con placeholder, `active:false`).
- `C_SLICE1_B10_smoke_a12_directo.ps1` — smoke directo (8 casos).

---

## 0) Decisiones que este bloque materializa (registrar al CIERRE del slice, no ahora)
- **D-C-48** — action congelada `cobranza.saldos`. Key del CATALOG == `EXPECTED_ACTION` del wrapper.
- **D-C-49** — A12 reusa la lógica de `vita_w09_listado_saldos`: universo `confirmada/activa` + `saldo_real > 0`, pagos normalizados, **sin** la fila centinela del workflow HTML.
- **Reafirma D-C-40 / D-9B-05** — saldo calculado desde pagos confirmados (`sena`+`saldo`, `monto_recibido`); `saldo_real = monto_total - total_pagado_confirmado`. `reservas.monto_saldo` NO es fuente operativa.
- Ajustes de esta sesión: (a) mapeo prereserva→reserva como **CTE agrupada `reserva_por_prereserva` (`MIN`)** en vez de subquery escalar (no hay UNIQUE en `reservas.id_pre_reserva`; la CTE no explota ante datos sucios); (b) `huesped` incluye **`email`** (telefono/email nullable individualmente, pero por regla del flujo al menos uno existe; sin dni ni notas internas).
- Contrato **mínimo** `data:{filas}` (sin `generado_en`). Montos numéricos crudos. Lista vacía → `filas:[]` con `ok:true` (D-C-47).

---

## 1) Importar el wrapper en n8n (TEST)
1. n8n Cloud → **Import from File** → `portal-a12-saldos__TEMPLATE.json`.
2. Verificá Webhook **path** `portal-a12-saldos` y **Raw Body = ON** (L-C-05; ya viene seteado).

## 2) Credencial Postgres TEST (2 nodos)
Asigná **vita_supabase_test** (placeholder `REEMPLAZAR_POR_CRED_TEST`) en:
- `leer_ambiente`
- `PG: leer saldos`

> Ambos `onError: continueRegularOutput` + `alwaysOutputData`. `PG: leer saldos` además `executeOnce`. **Sin `queryReplacement`** (CTEs sin parámetros).

## 3) Secreto HMAC — Modo B
En **`validar_firma_ts_rol`**, reemplazá `__PEGAR_SECRETO_O_USAR_VARIABLE__` por el **VITA_HMAC_SECRET real** (el mismo de A03/A04/A05/A06 en TEST). Assert por prefijo aborta si te lo olvidás (L-C-10). No commitear con el secreto pegado.

## 4) Activar el workflow
Activá `portal-a12-saldos` (toggle **Active**) → responde en `/webhook/portal-a12-saldos`.

---

## 5) (Informativo) ¿Cuántas reservas con saldo hay en TEST?
Solo para **saber qué esperar**. **No hace falta que haya ninguna** — el smoke pasa con `filas=0` (D-C-47). **No crear fixtures.** Esta query es **exactamente** lo que devuelve A12 (podés correrla read-only para ver las filas):

```sql
WITH reserva_por_prereserva AS (
  SELECT id_pre_reserva, MIN(id_reserva) AS id_reserva
  FROM reservas WHERE id_pre_reserva IS NOT NULL GROUP BY id_pre_reserva
),
pagos_reserva_normalizados AS (
  SELECT p.estado, p.tipo, p.monto_recibido,
         COALESCE(p.id_reserva, rpp.id_reserva) AS id_reserva_normalizado
  FROM pagos p LEFT JOIN reserva_por_prereserva rpp ON rpp.id_pre_reserva = p.id_prereserva
),
reservas_con_saldo AS (
  SELECT r.id_reserva, r.id_cabana, c.nombre AS cabana,
         r.fecha_checkin::TEXT AS fecha_checkin, r.fecha_checkout::TEXT AS fecha_checkout,
         r.monto_total, r.id_huesped,
         COALESCE(SUM(prn.monto_recibido) FILTER (
           WHERE prn.estado='confirmado' AND prn.tipo IN ('sena','saldo')),0) AS total_pagado_confirmado
  FROM reservas r
  JOIN cabanas c ON c.id_cabana = r.id_cabana
  LEFT JOIN pagos_reserva_normalizados prn ON prn.id_reserva_normalizado = r.id_reserva
  WHERE r.estado IN ('confirmada','activa')
  GROUP BY r.id_reserva, r.id_cabana, c.nombre, r.fecha_checkin, r.fecha_checkout, r.monto_total, r.id_huesped
  HAVING r.monto_total - COALESCE(SUM(prn.monto_recibido) FILTER (
           WHERE prn.estado='confirmado' AND prn.tipo IN ('sena','saldo')),0) > 0
)
SELECT rcs.id_reserva, rcs.cabana, rcs.fecha_checkin, rcs.fecha_checkout,
       rcs.monto_total, rcs.total_pagado_confirmado,
       (rcs.monto_total - rcs.total_pagado_confirmado)::numeric(12,2) AS saldo_real,
       TRIM(BOTH FROM (h.nombre || ' ') || COALESCE(h.apellido,'')) AS huesped_nombre,
       h.telefono AS huesped_telefono, h.email AS huesped_email
FROM reservas_con_saldo rcs
JOIN huespedes h ON h.id_huesped = rcs.id_huesped
ORDER BY rcs.fecha_checkin, rcs.id_reserva;
```
Si da 0 filas, los casos 1/2 igual deben devolver `ok:true | filas=0 | filas_presente=True`.

## 6) Completar y correr el smoke
En `C_SLICE1_B10_smoke_a12_directo.ps1`, CONFIG: `$Secret` = el VITA_HMAC_SECRET del nodo. (Sin IDs.) Corré:
```powershell
cd <carpeta>
powershell -ExecutionPolicy Bypass -File .\C_SLICE1_B10_smoke_a12_directo.ps1
```

---

## 7) Criterio de aceptación (8/8)

| # | Caso | Esperado |
|---|------|----------|
| 1 | vicky | `ok:true`, `filas_presente=True` (filas ≥ 0; **0 es válido**) |
| 2 | socio | `ok:true`, `filas_presente=True` (filas ≥ 0) |
| 3 | jenny | `ok:false`, `rol_no_permitido` |
| 4 | intruso | `ok:false`, `rol_no_permitido` |
| 5 | firma inválida | `ok:false`, `firma_invalida` |
| 6 | ts viejo (-10min) | `ok:false`, `ts_fuera_de_ventana` |
| 7 | ambiente cruzado (ops→test) | `ok:false`, `ambiente_incorrecto` (detail esperado=ops real=test) |
| 8 | action ajena (`prereservas.activas`) | `ok:false`, `accion_desconocida` |

Si hay ≥1 reserva con saldo, en 1/2 podés mirar (manualmente) que cada fila trae `monto_total`/`total_pagado_confirmado`/`saldo_real` numéricos y `huesped:{nombre,telefono,email}` (sin dni ni notas internas), y que `saldo_real = monto_total - total_pagado_confirmado > 0`.

---

## 8) Próximo bloque (no ahora)
Con 8/8: **cablear A12 en el gateway** (`portal-api`) — una línea en el CATALOG
```
'cobranza.saldos': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a12-saldos', validate: payloadVacio },
```
\+ deploy por Dashboard (verify_jwt OFF, L-C-06) + **smoke vía gateway**: `sesion.contexto` incluye `cobranza.saldos` para vicky/socio y no para jenny; vicky/socio → `ok:true` con `data.filas` array; jenny → `rol_no_permitido` (gateway); sin JWT → `no_autorizado`.

**A12 es la última lectura del Slice 1.** Con B10+B11 verdes, el slice queda completo (A03·A04·A05·A06·A12) y recién ahí se hace el cierre formal + actualización de satélites + registro de D-C-42..49 + limpieza de los comentarios stale del CATALOG.
