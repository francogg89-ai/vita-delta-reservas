# RUNSHEET — Slice 1 / Bloque 11 (cableado de A12 en el gateway) — ÚLTIMO BLOQUE DEL SLICE

Carril C / Portal Operativo Interno. **Entorno: TEST únicamente.** No toca OPS ni el schema canónico.
Cierra el camino de A12: la acción `cobranza.saldos` queda servida por `portal-api`. Pre-requisito:
el wrapper `portal-a12-saldos` ya pasó su smoke directo (Bloque 10, 8/8, con lista poblada verificada).

Artefactos del bloque:
- `C_SLICE1_B11_portal-api_index.ts` — gateway con A12 cableada (delta = **una sola entrada** en el CATALOG, después de `prereservas.activas`; los 2 comentarios stale se dejaron intactos para el cierre).
- `C_SLICE1_B11_smoke_a12_via_portal.ps1` — smoke vía gateway.

---

## 0) Qué cambió en el gateway (y qué NO)
- **+1 entrada** en el CATALOG: `'cobranza.saldos': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a12-saldos', validate: payloadVacio }` (+ su comentario, al estilo del resto).
- **Nada más.** `payloadVacio` ya estaba (no se tocó). Los comentarios stale quedan **a propósito** para limpiar en el cierre del slice. El header no se tocó.
- CATALOG resultante (Slice 1 completo): `sesion.contexto`, `calendario.limpieza`, `calendario.operativo`, `reserva.detalle`, `prereservas.activas`, `cobranza.saldos`.

## 1) Deploy del gateway (por Dashboard)
1. Supabase → Edge Functions → `portal-api` → pegar el contenido de `C_SLICE1_B11_portal-api_index.ts` → **Deploy**.
2. **CRÍTICO (L-C-06):** destildá **"Verify JWT with legacy secret"** (verify_jwt = OFF). Si queda ON, "sin JWT" no dará `no_autorizado`.
3. No cambian env vars ni secretos. El wrapper `portal-a12-saldos` debe seguir **activo** (de B10).

## 2) Correr el smoke vía gateway
`C_SLICE1_B11_smoke_a12_via_portal.ps1` ya viene con la publishable key de TEST. No requiere secreto ni IDs. Corré:
```powershell
cd <carpeta>
powershell -ExecutionPolicy Bypass -File .\C_SLICE1_B11_smoke_a12_via_portal.ps1
```

---

## 3) Criterio de aceptación (sin fallos)

| Usuario / caso | Esperado |
|---|---|
| vicky · sesion.contexto | INCLUYE `cobranza.saldos` |
| vicky · cobranza.saldos | `ok:true`, `data.filas` presente (array; en TEST hoy filas=3; **0 también es válido**) |
| franco (socio) · sesion.contexto | INCLUYE `cobranza.saldos` |
| franco (socio) · cobranza.saldos | `ok:true`, `data.filas` presente (array) |
| jenny · sesion.contexto | NO incluye `cobranza.saldos` |
| jenny · cobranza.saldos | `ok:false`, `rol_no_permitido` (rebota en el gateway, sin tocar n8n) |
| sin JWT · cobranza.saldos | `ok:false`, `no_autorizado` |

`filas=0` en vicky/socio es PASS (lista vacía válida, D-C-47).

---

## 4) Al terminar — Slice 1 COMPLETO
- 8/8 (B10, wrapper) + sin fallos (B11, gateway) ⇒ **A12 cerrada punta a punta**.
- **Slice 1 completo:** A03 ✓ · A04 ✓ · A05 ✓ · A06 ✓ · **A12 ✓**. El CATALOG del gateway sirve las 6 acciones (1 edge + 5 n8n).
- **Recién ahora se habilita el cierre formal del slice** (paso aparte, toca satélites — hasta acá intocados):
  1. Registrar decisiones **D-C-42..D-C-49** en `DECISIONES_NO_REABRIR.md`.
  2. Registrar lecciones nuevas en `Lecciones_Aprendidas.md` (p.ej.: `queryReplacement` para acciones con payload — A05; semántica de listas `filas:[]` ≠ `no_encontrado`; reuse de `vita_w09_listado_saldos` con CTE de mapeo agrupada en vez de subquery escalar; nota de robustez A05 vs A12 sobre normalización de pagos por prereserva).
  3. Actualizar `ESTADO_ACTUAL_VITA_DELTA.md` (Slice 1 cerrado; pendientes: Slice 2 escrituras, Slice 3a/3b, promoción OPS de Carril C).
  4. **Limpiar los 2 comentarios stale del CATALOG** (`Bloque 1A NO agrega ninguna` y `A04/A05/A06/A12 se agregan al cablearse`) — ahora que están las 5 acciones n8n cableadas.
  5. Commit de los 5 templates de wrapper + el `index.ts` final + los smokes, sanitizados.
- OPS y `6B_SCHEMA_SQL.md` siguen intocados: la promoción de Carril C a OPS es un carril aparte, posterior al cierre del slice.
