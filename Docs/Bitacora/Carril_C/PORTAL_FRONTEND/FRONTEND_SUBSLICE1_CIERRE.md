# Cierre — Frontend Sub-slice 1 (Portal Operativo Interno · Carril C): las 8 lecturas

**Carril:** C — Portal Operativo Interno (frontend).
**Entorno:** TEST (`vita-delta-test`). **No se tocó OPS ni el canónico (`6B_SCHEMA_SQL.md`).** Cero escrituras.
**Fecha de cierre:** 2026-06-24.
**Base:** `FRONTEND_SUBSLICE0_CIERRE.md` (shell), `CONTRATO_FRONTEND_PORTAL_v1.md` + `…_CIERRE.md`,
`CARRIL_C_BACKEND_API_DISENO_CIERRE.md`, `C_SLICE*_CIERRE.md` (wrappers backend) y la lectura directa
de los `portal-a*__TEMPLATE.json`. Parche backend asociado: `BLOQUE3_Y_A04A12_CONSISTENCIA_CIERRE.md`.

**Stack:** React 18 + Vite 5 + TypeScript strict + Tailwind 3 + Supabase JS (solo auth/sesión) +
`callPortal` (fetch) sobre el gateway `portal-api`. Paleta: ink / river / sand / mist / reed.
Ruta del frontend en el repo: `Apps/portal-operativo/`.

---

## 1. Alcance cerrado

Sub-slice 1 = **todas las pantallas de LECTURA** del portal (8), montadas sobre el shell del
sub-slice 0. Cada pantalla consume un wrapper *read* del gateway vía `callPortal` / `useAction`.
Sin escrituras, sin tocar backend salvo el parche de consistencia A04/A12 (cerrado aparte).

### Las 8 lecturas (inventario)

| Action | Pantalla | Ruta | Forma clave de `data` |
|---|---|---|---|
| `calendario.limpieza` (A03) | `CalendarioLimpieza` | `/calendarios/limpieza` | HTML en iframe (single-view) |
| `calendario.operativo` (A04) | `CalendarioOperativo` | `/calendarios/operativo` | HTML en iframe (multi-mes apilado) |
| `reserva.detalle` (A05) | `ReservaDetalle` | `/reservas/detalle` | objeto reserva + `pagos[]` (todas las líneas) |
| `prereservas.activas` (A06) | `PrereservasActivas` | `/reservas/prereservas` | `filas[]` (huésped anidado) |
| `cobranza.saldos` (A12) | `CobranzaSaldos` | `/cobranzas/saldos` | `filas[]` con `id_reserva`, saldo_real > 0 |
| `historico.reservas` (A24) | `HistoricoReservas` | `/reservas/historico` | `{filas, limit, offset, total}` |
| `ingresos.cobrados_periodo` (A25) | `IngresosPeriodo` | `/economico/ingresos` | `{total_cobrado, total, por_*[], otros_movimientos, filas, limit, offset}` |
| `gastos.listado` (A13) | `GastosListado` | `/economico/gastos` | `{total_gastos, por_clase[], filas, limit, offset}` — **sin `total`** |

---

## 2. Bloques (resumen de entrega)

- **Bloque 1** — router / shell / hook / UI base (D-FE-12, 13, 17, 18). Tarball validado.
- **Bloque 2** — calendarios A03/A04 (D-FE-14) + 2 parches: shim CSS *scriptless* para apilar meses
  bajo `sandbox` sin `allow-scripts`, y autosize del iframe. Validado.
- **Bloque 3** — lecturas JSON A05/A06/A12 (`DataTable`, `EstadoBadge`). Validado.
- **Parche consistencia A04/A12 (backend n8n)** — A04 alineado al criterio de saldo de A12 +
  notas + display clampeado. Aplicado y aprobado en TEST. Decisiones D-C-61/62/63 en su propio cierre.
- **Bloque 4a** — A24 con filtros completos (check-in desde/hasta, cabaña, estado, texto) +
  paginación server-side (`Paginador`, `CABANAS_TEST`/P-FE-01). Validado.
- **Bloque 4b** — A25 + A13: selector de mes con floor, agregados (cards + desgloses) +
  paginación (A25 con `total`; A13 derivando el conteo de `Σ por_clase.n`). Validado.

---

## 3. Decisiones lockeadas durante el sub-slice 1 (🔒 no reabrir)

**Frontend (D-FE):**
- **D-FE-12** — Router `react-router-dom` v6: `<BrowserRouter>` en App; `app/rutas.tsx` mapea
  `action → componente`; `Menu` con `<NavLink>`; la URL es la fuente; deep-link + refresh persisten;
  ruta desconocida → `/`.
- **D-FE-13** — Hook único `useAction<T>(action, payload, {enabled})` → `{data, loading, error, refetch}`,
  con protección contra setState-tras-unmount y respuestas fuera de orden (flag + reqId); patrón
  draft→applied para filtros.
- **D-FE-14** — Calendarios A03/A04 con `<iframe srcDoc sandbox="allow-same-origin">` (sin
  `allow-scripts`); A04 apila meses vía shim CSS inyectado en `onLoad`; autosize leyendo el doc.
- **D-FE-15** — `DataTable` compartido + paginación **server-side** (`limit`/`offset`, página 50).
  A24/A25 usan `total`; A13 deriva el conteo de `Σ por_clase.n`.
- **D-FE-16** — Filtros nativos (`type=date` / `type=month`) con floor **2026-07-01** (`min` + nota);
  `CABANAS_TEST` como constante **solo TEST** → **P-FE-01**; estados del enum del contrato.
- **D-FE-17** — `RutaProtegida action="…"`: si la action no está en `contexto.acciones` → redirect `/`
  + aviso ámbar. Espeja D-FE-09 y el `rol_no_permitido` del backend.
- **D-FE-18** — Componentes en `src/ui/`: `Money` (ARS es-AR, **nunca /100**, negativos en rojo),
  `Fecha`, `EstadoBadge`, `Cargando`, `Vacio`, `ErrorCard`, `DataTable`, `Paginador`, `CalendarFrame`.

**Backend (surgidas en la integración, detalle en `BLOQUE3_Y_A04A12_CONSISTENCIA_CIERRE.md`):**
- **D-C-61** — A04 usa `saldo_real` recomputado (criterio A12), no `vista_calendario.monto_saldo`.
- **D-C-62** — A04 display = `max(saldo_real, 0)`; no se exponen sobrepagos/créditos en el calendario.
- **D-C-63** — Política de notas: `notas`/`notas_reserva` visibles para {vicky, socio} en A04 y A05;
  no a jenny ni a web pública salvo decisión específica.

---

## 4. Lecciones (🔒)

- **L-FE-01** — Errores de consola de **extensiones de wallet** del navegador ≠ errores de la app;
  discriminar por origen del mensaje; chequeo definitivo en perfil incógnito/sin extensiones.
- **L-FE-02** — Los montos del backend llegan **en pesos** como number (`numeric(12,2)`); "centavos"
  es solo técnica interna de suma del backend/render. El frontend **nunca divide por 100**.

---

## 5. Mapa del código nuevo (sub-slice 1)

```
src/
├─ app/        App.tsx · AppShell.tsx · Menu.tsx · rutas.tsx · RutaProtegida.tsx · Home.tsx
├─ hooks/      useAction.ts
├─ lib/        contratos.ts · formato.ts · constantes.ts · periodo.ts
├─ ui/         Money · Fecha · EstadoBadge · Cargando · Vacio · ErrorCard · DataTable · Paginador · CalendarFrame
└─ screens/    Calendarios (A03/A04) · ReservaDetalle (A05) · PrereservasActivas (A06) ·
               CobranzaSaldos (A12) · HistoricoReservas (A24) · IngresosPeriodo (A25) · GastosListado (A13)
```

`callPortal.ts`, `AuthProvider.tsx`, `actionRegistry.ts` (D-FE-09, presentación-only) provienen del
sub-slice 0 y **no se modificaron**.

---

## 6. Hallazgos / discrepancias contrato vs wrapper (consolidado)

- **Huésped anidado** (`huesped:{nombre,telefono[,email]}`) en A06/A12/A24, no plano.
- **A04** leía saldo documental → recomputa `saldo_real` (criterio A12); display clampeado a `$0`.
- **A24** filtra por **`fecha_checkin`** con floor duro (`GREATEST`): reservas con check-in en junio
  (p. ej. #13) **no** aparecen en A24 aunque sí en A12 (que no tiene floor). Esperado.
- **A25** `total_cobrado`/`total` y `filas` son sobre **caja = seña+saldo**; extra/ajuste/reembolso
  van aparte en `otros_movimientos` y **no** suman al total (el `extra` generalmente es el recargo ~5% al pagar
  saldo por Mercado Pago). `mes` por `date_trunc` sobre `created_at`. Pagina en el render. **Sin
  check de inversión** de período.
- **A13** **no trae `total`** (conteo = `Σ por_clase.n`); filtra por **`periodo`** (mes contable)
  truncado a primer día de mes. Clases A/C/D/E (A=común, C=común op., D=zona, E=cabaña).
- **Rango invertido (desde > hasta):** A24 → **error**; A25/A13 → **vacío** (sin error). La UI lo
  refleja como estado vacío.

---

## 7. Pendientes abiertos (→ propagación a satélites, sección 8)

- **P-FE-01** — `CABANAS_TEST` no portable (IDs 1–5 solo TEST; DEV 17–21; OPS otros) → reemplazar por
  un **endpoint de catálogo** antes de promover a OPS.
- **Anti-sobrecobro (pre-OPS)** — validar que todos los flujos de cobro impidan sobrecobro no
  intencional (en especial **A10** y los futuros flujos web / **Mercado Pago**); aceptar
  sobrepago/crédito debe ser decisión **explícita**.
- **Limpieza de datos TEST** — pagos duplicados/sobre `monto_total` en TEST → mini-etapa separada
  (escritura acotada por id, con backup), si hace falta. No bloqueante.
- **UX diferidas (sin patch ahora):**
  - Evitar desde el frontend `fecha_hasta < fecha_desde` (A24) y el rango de meses invertido (A25/A13).
  - Aclaración explícita en A25 ("pagos según fecha de cobro, no de estadía") y en A13 ("período contable").
- **A13 filtros `id_zona` / `id_cabana`** — diferidos hasta que exista catálogo (familia P-FE-01).
- **A05 `nota` / `notas_reserva`** — incluir formalmente en el contrato (la prosa original no las
  enumeraba; D-C-63 resolvió la visibilidad).

---

## 8. Propagación a satélites — plan a ejecutar (Franco pasa los archivos)

Una sola pasada coordinada, **respetando el EOL de cada archivo** (asserts `count==1` sobre anclas
únicas, preservación de EOL por archivo).

| Destino | EOL | Contenido a propagar |
|---|---|---|
| `DECISIONES_NO_REABRIR.md` | LF | D-FE-12 … D-FE-18 · D-C-61 · D-C-62 · D-C-63 |
| `Lecciones_Aprendidas.md` | CRLF | L-FE-01 · L-FE-02 |
| `Pendiente_pre_produccion.md` | LF | P-FE-01 · anti-sobrecobro (A10/web/MP) · limpieza TEST · UX diferidas (inversión + aclaraciones A25/A13) · A13 id_zona/id_cabana · A05 notas en contrato |
| `ESTADO_ACTUAL_VITA_DELTA.md` | CRLF | Portal: sub-slice 0 + sub-slice 1 (8 lecturas) cerrados; próximo = escrituras |

*(L-FE-01 puede ya estar en `Lecciones_Aprendidas.md`; al recibir el archivo verifico antes de
agregar para no duplicar.)*

---

## 9. Estado y próximo paso

- **Sub-slice 1 (lecturas) — CERRADO.** Las 8 pantallas de lectura funcionan en TEST con validación
  por rol (jenny solo ve el calendario de limpieza; vicky/socios ven todo).
- **Próximo:** pantallas de **ESCRITURA** — A07 `reserva.crear_manual`, A08 `bloqueo.crear_manual`,
  A10 `cobranza.registrar_saldo`, A11 `cargar.gasto_interno`. Sub-slice con diseño y decisiones
  propias; ahí entra de lleno el pendiente **anti-sobrecobro** (revalidación previa a confirmar).
