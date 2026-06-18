# RUNSHEET — Slice 1 / Bloque 9 (cableado de A06 en el gateway)

Carril C / Portal Operativo Interno. **Entorno: TEST únicamente.** No toca OPS ni el schema canónico.
Cierra el camino de A06: la acción `prereservas.activas` queda servida por `portal-api`. Pre-requisito:
el wrapper `portal-a06-prereservas` ya pasó su smoke directo (Bloque 8, 8/8).

Artefactos del bloque:
- `C_SLICE1_B9_portal-api_index.ts` — gateway con A06 cableada (delta = **una sola entrada** en el CATALOG, después de `reserva.detalle`; los 2 comentarios stale se dejaron intactos para el cierre).
- `C_SLICE1_B9_smoke_a06_via_portal.ps1` — smoke vía gateway.

---

## 0) Qué cambió en el gateway (y qué NO)
- **+1 entrada** en el CATALOG: `'prereservas.activas': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a06-prereservas', validate: payloadVacio }` (+ su comentario, al estilo A03/A04/A05).
- **Nada más.** `payloadVacio` ya estaba definido (no se tocó). Los comentarios stale (`Bloque 1A NO agrega ninguna` y `A04/A05/A06/A12 se agregan al cablearse`) quedan **a propósito** para limpiar en el cierre del slice. El header no se tocó.
- CATALOG resultante: `sesion.contexto`, `calendario.limpieza`, `calendario.operativo`, `reserva.detalle`, `prereservas.activas`.

## 1) Deploy del gateway (por Dashboard)
1. Supabase → Edge Functions → `portal-api` → pegar el contenido de `C_SLICE1_B9_portal-api_index.ts` → **Deploy**.
2. **CRÍTICO (L-C-06):** después de cada deploy, destildá **"Verify JWT with legacy secret"** (verify_jwt = OFF). Si queda ON, el caso "sin JWT" no dará `no_autorizado`.
3. No cambian env vars ni secretos. El wrapper `portal-a06-prereservas` debe seguir **activo** (de B8).

## 2) Correr el smoke vía gateway
`C_SLICE1_B9_smoke_a06_via_portal.ps1` ya viene con la publishable key de TEST. No requiere el secreto HMAC (el gateway firma del lado servidor) ni IDs. Corré:
```powershell
cd <carpeta>
powershell -ExecutionPolicy Bypass -File .\C_SLICE1_B9_smoke_a06_via_portal.ps1
```

---

## 3) Criterio de aceptación (sin fallos)

| Usuario / caso | Esperado |
|---|---|
| vicky · sesion.contexto | INCLUYE `prereservas.activas` |
| vicky · prereservas.activas | `ok:true`, `data.filas` presente (array; **filas=0 es válido**) |
| franco (socio) · sesion.contexto | INCLUYE `prereservas.activas` |
| franco (socio) · prereservas.activas | `ok:true`, `data.filas` presente (array) |
| jenny · sesion.contexto | NO incluye `prereservas.activas` |
| jenny · prereservas.activas | `ok:false`, `rol_no_permitido` (rebota en el gateway, sin tocar n8n) |
| sin JWT · prereservas.activas | `ok:false`, `no_autorizado` |

`filas=0` en vicky/socio es PASS (lista vacía válida, D-C-47). No se crean fixtures.

---

## 4) Al terminar
- 8/8 (B8, wrapper) + sin fallos (B9, gateway) ⇒ **A06 cerrada punta a punta**.
- **No se tocan satélites** todavía: D-C-45/46/47 quedan confirmadas por evidencia, a registrar en el cierre formal del slice junto con A12.
- Estado Slice 1: A03 ✓, A04 ✓, A05 ✓, **A06 ✓**. Falta **A12** (saldos de cobranza) para el cierre. A12 es lista JSON `data:{filas}` igual que A06 (mismo spine, mismo cableado, render lista); el contenido es el recálculo de saldos por reserva (reafirma D-C-40, como en A05).
