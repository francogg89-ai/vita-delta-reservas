# RUNSHEET — Frontend Sub-slice 2 / Bloque B1 (cimientos de escritura)

**Carril:** C — Portal Operativo Interno (frontend). **Entorno:** TEST. **Cero backend / n8n / OPS / canónico.**
**Base:** sub-slice 0 (shell) + sub-slice 1 (8 lecturas), ambos cerrados. **Build baseline previo:** typecheck+build EXIT 0.
**Alcance B1:** los **cimientos** de las 4 escrituras (A07/A08/A10/A11). **No agrega pantallas ni rutas** — eso entra en B2–B5. Por eso B1 **no tiene matriz de prueba por rol** todavía (no hay UI nueva navegable); su verificación es el typecheck+build y la prueba de que los archivos están en el set de tipado. La matriz por rol aparece desde B2 (A08).

---

## 1. Qué incluye B1 (9 archivos)

**Nuevos (7):**
- `src/hooks/useEnviar.ts` — hook único de escritura (**D-FE-19/20/22**): anti-doble-click, ciclo de `idempotency_key` (key nueva por submit; `reintento` reusa la retenida; `reset()` la suelta), transporte por acción (`'none'`/`'payload'`/`'sibling'`, **D-FE-02**), `estadoIncierto` como flag aparte, guard contra setState tras unmount. Sin localStorage/sessionStorage.
- `src/lib/erroresEscritura.ts` — `mensajeUsuario(error)` (familia B → mensaje genérico; familia A → message del backend) y `esEstadoIncierto(error)` (**D-FE-25**; refleja **P-FE-07**: `detail.constraint` no llega por el gateway, los mensajes finos salen de pre-validación).
- `src/ui/estilos.ts` — clases Tailwind compartidas (`controlClass`, `botonPrimario`, `botonSecundario`), mobile-first (ancho completo, `text-base` para no disparar el zoom de iOS).
- `src/ui/Campo.tsx` — label + control + error/hint (el `<label>` envuelve el control = área tappable).
- `src/ui/BotonSubmit.tsx` — submit con spinner + `disabled` por validación (refuerza el anti-doble-click de `useEnviar`).
- `src/ui/TarjetaExito.tsx` — tarjeta de éxito con acciones (**D-FE-25**).
- `src/ui/Banner.tsx` — banner por tono (`aviso`/`error`/`incierto`/`info`) con acciones (para `conflicto` y `estado_incierto`, **D-FE-22**).

**Modificados (2, archivo completo):**
- `src/lib/contratos.ts` — **+4 tipos de respuesta de escritura** (forma EXACTA de los wrappers/función):
  - `CrearReservaData = { id_reserva, id_pre_reserva, id_huesped, idempotent_match }`
  - `CrearBloqueoData = { id_bloqueo, id_cabana, tipo_bloqueo }`
  - `RegistrarSaldoData = { id_pago, estado_pago, idempotent_match, saldo_real_actual, saldo_real_previo? }`
  - `CargarGastoData = { id_gasto, idempotente }` ← la clave es `idempotente` (no `idempotent_match`).
- `src/lib/constantes.ts` — **+`SOCIOS_TEST`** (1 Franco · 2 Rodrigo · 3 Remo), **+`ZONAS_TEST`** (1 grandes · 2 chicas), **+enums** `MOTIVOS_BLOQUEO`, `MEDIOS_PAGO_RESERVA` (con `mp_link`), `MEDIOS_PAGO_COBRO` (sin `mp_link`), `PAGADORES_GASTO`. Todos los catálogos confirmados por snapshot read-only en TEST (2026-06-24) y marcados TEST-only bajo **P-FE-01/P-FE-05**.

`callPortal.ts`, `useAction.ts`, `actionRegistry.ts`, `rutas.tsx` y todas las pantallas/atoms previos **no se tocan**.

---

## 2. Cómo aplicar

1. Extraé el tarball **en la raíz del repo** (`vita-delta-reservas/`): coloca/reemplaza los 9 archivos bajo `Apps/portal-operativo/src/...`.
   ```
   tar -xzf portal-operativo-b1-cimientos.tar.gz
   ```
   (O reemplazá manualmente: 7 nuevos + `contratos.ts` y `constantes.ts` completos.)
2. No hace falta `npm install` (sin dependencias nuevas).

---

## 3. Verificación (la que corro yo antes de entregar; reproducila)

```
cd Apps/portal-operativo
npm run typecheck   # tsc --noEmit
npm run build       # tsc && vite build
```

**Resultado esperado / obtenido en mi corrida:**
- `typecheck` → **EXIT 0**, sin errores.
- `build` → **EXIT 0**; `✓ 107 modules transformed` (igual que el baseline: los átomos/hook todavía no están importados por ninguna pantalla, así que no entran al bundle; sí los type-chequea `tsc` por `include:["src"]`).
- Prueba de tipado: `npx tsc --noEmit --listFiles` incluye los 9 archivos de B1.

> El bundle sin cambiar de tamaño es lo esperado en B1: son cimientos. Empiezan a usarse (y a entrar al bundle) en B2.

---

## 4. Decisiones materializadas

- **D-FE-19** `useEnviar` · **D-FE-20** ciclo de key · **D-FE-22** `estado_incierto` (flag) · **D-FE-25** tarjeta de éxito + familias de error.
- **D-FE-02** transporte de key (`'payload'` A10 / `'sibling'` A11 / `'none'` A07/A08) cableado en el hook.
- **D-FE-24** catálogos TEST confirmados (`SOCIOS_TEST`/`ZONAS_TEST`/`CABANAS_TEST`) — pre-OPS sigue P-FE-01/05.
- **P-FE-07** reflejado en `erroresEscritura.ts` (el gateway anula `detail` → mensajes finos por pre-validación).
- Criterios de blueprint: mobile-first (`estilos.ts`) y sin localStorage/sessionStorage (estado en React).

---

## 5. Próximo: B2 — A08 `bloqueo.crear_manual`

Primera pantalla de escritura (la más simple: sin key, 5 campos), que **consume** los cimientos de B1 (`useEnviar('bloqueo.crear_manual','none')`, `Campo`/`BotonSubmit`/`TarjetaExito`/`Banner`, `MOTIVOS_BLOQUEO`, `CABANAS_TEST`, `CrearBloqueoData`) + cableo en `rutas.tsx` (reemplaza el `PlaceholderView`). Ahí arranca la matriz de prueba por rol (jenny no la ve; vicky/socio sí) y la UX de `estado_incierto` → "Ver calendario operativo".
