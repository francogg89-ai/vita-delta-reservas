# RUNSHEET — Slice 1 / Bloque 7 (cableado de A05 en el gateway)

Carril C / Portal Operativo Interno. **Entorno: TEST únicamente.** No toca OPS ni el schema canónico.
Cierra el camino de A05: la acción `reserva.detalle` queda servida por `portal-api`. Pre-requisito:
el wrapper `portal-a05-detalle` ya pasó su smoke directo (Bloque 6, 14/14).

Artefactos del bloque:
- `C_SLICE1_B7_portal-api_index.ts` — gateway con A05 cableada (delta = **una sola entrada** en el CATALOG, después de `calendario.operativo`; los 2 comentarios stale se dejaron intactos para el cierre).
- `C_SLICE1_B7_smoke_a05_via_portal.ps1` — smoke vía gateway (camino completo, con payload).

---

## 0) Qué cambió en el gateway (y qué NO)
- **+1 entrada** en el CATALOG: `'reserva.detalle': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a05-detalle', validate: payloadIdReserva }` (+ su comentario, al estilo A03/A04).
- **Nada más.** `payloadIdReserva` ya estaba definido (no se tocó). Los comentarios stale (`Bloque 1A NO agrega ninguna` y `A04/A05/A06/A12 se agregan al cablearse`) quedan **a propósito** para limpiar en el cierre del slice. El header no se tocó (igual que en B5).
- Doble allowlist activa (D-C-39): el gateway impone `roles` y el wrapper revalida `ROLES_OK`. Action binding (D-C-41/42): key del CATALOG == `EXPECTED_ACTION` del wrapper.

## 1) Deploy del gateway (por Dashboard)
1. Supabase → Edge Functions → `portal-api` → pegar el contenido de `C_SLICE1_B7_portal-api_index.ts` → **Deploy**.
2. **CRÍTICO (L-C-06):** después de cada deploy, el editor re-activa "Verify JWT with legacy secret". **Destildalo** (verify_jwt = OFF). Si queda ON, el gateway no puede devolver el envelope uniforme para JWT faltante/inválido y el caso "sin JWT" no dará `no_autorizado`.
3. No cambian env vars ni secretos: el gateway ya tiene `SUPABASE_URL`, secret key, `VITA_HMAC_SECRET`, `VITA_AMBIENTE=test`, `N8N_BASE_URL`. El wrapper `portal-a05-detalle` debe seguir **activo** (de B6).

## 2) Correr el smoke vía gateway
`C_SLICE1_B7_smoke_a05_via_portal.ps1` ya viene con `$IdReservaOk=4`, `$IdReservaInexistente=1000013` y la publishable key de TEST. Verificá esos valores y corré:
```powershell
cd <carpeta>
powershell -ExecutionPolicy Bypass -File .\C_SLICE1_B7_smoke_a05_via_portal.ps1
```
(No requiere el secreto HMAC: el gateway firma del lado servidor. Solo necesita la publishable key + los logins de los 3 usuarios.)

---

## 3) Criterio de aceptación (sin fallos)

| Usuario / caso | Esperado |
|---|---|
| vicky · sesion.contexto | INCLUYE `reserva.detalle` |
| vicky · reserva.detalle (id 4) | `ok:true`, `data.reserva.id_reserva = 4` |
| vicky · reserva.detalle (id 1000013) | `ok:false`, `no_encontrado` |
| franco (socio) · sesion.contexto | INCLUYE `reserva.detalle` |
| franco (socio) · reserva.detalle (id 4) | `ok:true`, `data.reserva.id_reserva = 4` |
| franco (socio) · reserva.detalle (id 1000013) | `ok:false`, `no_encontrado` |
| jenny · sesion.contexto | NO incluye `reserva.detalle` |
| jenny · reserva.detalle (id 4) | `ok:false`, `rol_no_permitido` (rebota en el gateway, sin tocar n8n) |
| payload `{}` (id ausente) · vicky | `ok:false`, `payload_invalido` (rechazo en gateway, antes de firmar) |
| payload id string `"42"` · vicky | `ok:false`, `payload_invalido` |
| payload id negativo `-5` · vicky | `ok:false`, `payload_invalido` |
| payload id decimal `4.5` · vicky | `ok:false`, `payload_invalido` |
| payload id no-safe `1e20` · vicky | `ok:false`, `payload_invalido` |
| sin JWT · reserva.detalle | `ok:false`, `no_autorizado` |

Los 5 casos de payload inválido cierran la **defensa en profundidad**: el gateway (1ra defensa, `payloadIdReserva`) los rechaza antes de firmar; en B6 el wrapper (2da defensa) los rechazó al pegarle directo. Ambas capas cubiertas.

---

## 4) Al terminar
- 14/14 (B6, wrapper) + sin fallos (B7, gateway) ⇒ **A05 cerrada punta a punta**.
- **No se tocan satélites** todavía: D-C-42/43/44 quedan confirmadas por evidencia, a registrar en el cierre formal del slice junto con A06/A12.
- Próximo: A06/A12 (prereservas/saldos), contrato `data:{filas}` JSON — mismo security spine y cableado; cambia el render (lista) y el `validate` (payloadVacio).
