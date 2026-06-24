# Cierre — Bloque 3 (frontend A05/A06/A12) + Consistencia A04/A12 + Política de notas

**Carril:** C — Portal Operativo Interno. Frontend sub-slice 1 (Bloque 3) + un parche de
consistencia en el wrapper backend A04 (Carril C backend) surgido durante la integración.
**Entorno:** TEST (`vita-delta-test`). **No se tocó OPS ni el canónico (`6B_SCHEMA_SQL.md`).**
**Fecha:** 2026-06-24.
**Base:** blueprint del sub-slice 1 (D-FE-12…18, L-FE-02) + `C_SLICE1_CIERRE.md` (A05/A06/A12 backend)
+ `CARRIL_C_BACKEND_API_DISENO_CIERRE.md`.

---

## 1. Qué se cerró

### 1.1 Bloque 3 — lecturas JSON (frontend TEST)
Pantallas reales sobre el shell (Bloques 1–2): **A05 `reserva.detalle`** (buscador por id +
vista de detalle + tabla de pagos), **A06 `prereservas.activas`** y **A12 `cobranza.saldos`**
(listas con `DataTable`). Componentes nuevos: `DataTable`, `EstadoBadge`; tipos de respuesta en
`lib/contratos.ts`. Validado en TEST: listas pobladas y vacías (`filas:[]` ≠ error, D-C-47),
`no_encontrado` suave en A05, montos en pesos (L-FE-02, sin /100), guard por rol (jenny bloqueada).

### 1.2 A12 — columna "Reserva"
A12 ya devolvía `id_reserva` en `filas` → patch **frontend puro**: primera columna `#id`. Validado.

### 1.3 A04 — consistencia de saldo (parche backend en n8n TEST, aplicado y aprobado)
A04 leía `monto_saldo` **documental** de `vista_calendario` (no recomputaba con cobranzas
posteriores). Se alineó al criterio de A12. Aplicado por edición de 2 nodos (`PG: leer detalle`
+ `Code: render envelope`); HMAC/webhook/credenciales/conexiones/OPS intactos. Resultado validado:
saldos correctos, recambios OK, negativos por sobrepago mostrados como `$0`, notas operativas
visibles debajo del teléfono, autosize y A03 sin regresión.

### 1.4 A05 — notas visibles
A05 detalle muestra `notas` / `notas_reserva` (decisión D-C-63). No requirió patch (la pantalla
del Bloque 3 ya las mostraba). Se mantienen mascotas/niños (datos operativos del huésped).

---

## 2. Decisiones registradas 🔒 (no reabrir)

- **D-C-61** — **A04 fuente de saldo = `saldo_real` recomputado** (`monto_total − SUM(pagos
  confirmados sena/saldo)`, con normalización por prereserva idéntica a A12: CTE
  `reserva_por_prereserva` con `MIN` + `COALESCE(id_reserva, vía id_prereserva)`). **No** se usa
  `vista_calendario.monto_saldo` (documental) — reafirma D-C-40 ("`reservas.monto_saldo` no es
  fuente operativa"). `vista_calendario` **no se modifica**: el recálculo vive en la query del
  wrapper (LEFT JOIN a `pagos` + CTE). Aplica a los dos caminos del render: reserva normal (`r.`)
  y recambio "Entra X" (`c.entra.`).

- **D-C-62** — **A04 display del saldo = `max(saldo_real, 0)`** (`saldoVisible()` en el render).
  El `saldo_real` crudo (incl. **negativo** por sobrepago) se conserva en el cálculo, pero el
  calendario muestra `$0` cuando es ≤ 0. **No se exponen sobrepagos/créditos en el calendario
  operativo.** Mostrar crédito/sobrepago sería una decisión explícita futura (reportes/detalle),
  nunca accidental.

- **D-C-63** — **Política de visibilidad de notas operativas de reserva.** Las notas de reserva
  (`notas` / `notas_reserva`) son **datos operativos internos visibles para roles {vicky, socio}**:
  en A04 calendario operativo (compactas, escapadas, debajo del teléfono) y en A05 detalle.
  **No** se exponen a **jenny** ni a una **futura web pública de clientes** salvo decisión
  específica. Si en el futuro existieran notas **privadas/sensibles**, deben modelarse en un campo
  separado y **no** exponerse por defecto. *Esta decisión resuelve la tensión con el contrato
  original (`CONTRATO_FRONTEND_PORTAL_v1.md`), cuya enumeración de A05 no incluía las notas: quedan
  habilitadas para uso interno.*

---

## 3. Lecciones / notas

- **Trampa `monto_saldo` en A04:** el render usaba el saldo documental en **dos** caminos (normal
  y recambio). El verificador estructural del builder lo detectó (listar todas las ocurrencias
  antes de reemplazar evita arreglar solo la mitad).
- **Negativos = sobrepago real en TEST**, no bug de cálculo: pagos confirmados que superan
  `monto_total` (fixtures de pruebas de cobranza posterior). Se decidió **no** limpiarlos ahora.

---

## 4. Pendientes abiertos

- **Pre-OPS (→ `Pendiente_pre_produccion.md`):** validar que **todos los flujos productivos de
  cobro impidan sobrecobro no intencional**, en particular **A10 `cobranza.registrar_saldo`** y los
  futuros flujos web / **Mercado Pago**. Aceptar sobrepago/crédito debe ser una decisión explícita.
- **Limpieza de datos TEST (mini-etapa separada, si hace falta):** depurar pagos duplicados/sobre
  `monto_total` en TEST. Diferida para no romper smokes/reportes históricos de TEST. Sería una
  **escritura** acotada por id, con backup, ejecutada por Franco.

---

## 5. Propagación a satélites — EN COLA para el cierre del sub-slice 1

Per metodología (satélites se actualizan en el **cierre formal de etapa**), la propagación se hace
en **una pasada coordinada** en `FRONTEND_SUBSLICE1_CIERRE.md` (después del Bloque 4), respetando
los EOL por archivo. Queda **en cola** lo siguiente, ya documentado aquí:

| Destino | EOL | Contenido a propagar |
|---|---|---|
| `DECISIONES_NO_REABRIR.md` | LF | D-FE-12…18 · D-C-61 · D-C-62 · D-C-63 |
| `Lecciones_Aprendidas.md` | CRLF | L-FE-02 (montos en pesos, `Money` nunca /100) |
| `Pendiente_pre_produccion.md` | LF | Anti-sobrecobro (A10 / web / MP) · P-FE-01 (reemplazar `CABANAS_TEST` por catálogo) · limpieza datos TEST |
| `ESTADO_ACTUAL_VITA_DELTA.md` | CRLF | Estado del portal: Bloques 1–3 + A04/A12 consistentes; Bloque 4 pendiente |

---

## 6. Estado del sub-slice 1

- **Hecho:** Bloque 1 (router/shell/hook/UI base) · Bloque 2 (calendarios A03/A04 + shim) ·
  Bloque 3 (A05/A06/A12) · parche consistencia A04/A12.
- **Pendiente:** **Bloque 4 — A24/A25/A13** (reportes con filtros + paginación) → último de las 8
  lecturas. Al cerrarlo: `FRONTEND_SUBSLICE1_CIERRE.md` + propagación coordinada (sección 5).
