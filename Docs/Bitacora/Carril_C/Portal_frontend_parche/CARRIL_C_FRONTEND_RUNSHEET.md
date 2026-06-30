# Bloque C — Frontend TEST · Runsheet de ejecucion (A26 → A07/A08)

> Calendario propio liviano (Opcion B) cableado en CrearReserva (A07) y CrearBloqueo (A08).
> Sin dependencias nuevas. Strings YMD. A26 como lectura preventiva. Backend = autoridad.
> **Solo TEST.** Claude genero y valido; Franco ejecuta (git + Vercel).

---

## 1. Alcance (exactamente lo aprobado)

**Nuevos (3):**
- `src/lib/fecha.ts` (80 lineas) — primitivas YMD: `hoyAR()`/`mananaAR()` (Intl AR, espejo de `fecha_hoy_ar()`), `sumarDias` y navegacion de mes (aritmetica en UTC, sin corrimiento).
- `src/lib/disponibilidad.ts` (96) — logica pura: `esNocheElegible`, `nochesDelRango`, `inicioValido` (modo-aware), `validarRango` (half-open + cruce de mes), `maxFinSeleccionable` (cap en primera noche ocupada).
- `src/ui/CalendarioRango.tsx` (345) — grilla mensual de 1 cabana, controlada, A26 por mes con cache atada a la cabana **+ blindaje anti-respuesta-stale** (ignora respuestas de otra cabana usando `id_cabana` por dia).

**Editados (3, diffs localizados):**
- `src/lib/contratos.ts` — append: tipos `EstadoDisponibilidad`, `DiaDisponibilidad`, `DisponibilidadCabanaData` (A26).
- `src/screens/CrearReserva.tsx` (A07) — 5 cambios: imports; espejo `fecha_in < hoyAR` en `validar()`; helper `textoErrorReserva`; banner; swap de los 2 `<input type="date">` por `<CalendarioRango modo="reserva">`.
- `src/screens/CrearBloqueo.tsx` (A08) — 5 cambios: imports; espejo `fecha_hasta <= hoyAR` en `validar()` (NO `fecha_desde`); helper `textoErrorBloqueo`; banner; swap por `<CalendarioRango modo="bloqueo">`.

**No se toco:** OPS, backend, SQL/canonico, A26, gateway, `actionRegistry`, dependencias, motor horarios/recambio/precios, web publica. `useEnviar` y el submit de A07/A08 quedan intactos (el payload se sigue armando desde `form.*`).

---

## 2. Evidencia de validacion (corrida por Claude en clon TEST)

| Check | Resultado |
|---|---|
| `npx tsc --noEmit --strict` | **EXIT 0** |
| `npm run build` (`tsc && vite build`) | **EXIT 0** |
| `git diff` en `package.json` / `package-lock.json` | **vacio** (sin deps nuevas) |
| Dependencies declaradas | 4, sin cambios (`@supabase/supabase-js`, `react`, `react-dom`, `react-router-dom`) |
| Bundle JS | 454.07 kB → **462.12 kB** (+8.05 kB raw / +2.57 kB gzip). Modulos 120 → 123 (los 3 nuevos). El crecimiento es TSX propio, no una lib (una lib de fechas sumaria decenas de kB). |
| Harness de logica pura (esbuild + node, escenario oraculo Tokio) | **PASS=22 / FAIL=0** (18 de matriz + 4 del blindaje anti-stale) |

---

## 3. Matriz minima — cobertura

Probado a nivel **logica** (harness, IDs T1–T18) + **tipos/compilacion** (tsc+build). Lo visual queda para tu smoke en Vercel (seccion 5).

### A07 (reserva)
| Criterio | Cubierto por | Evidencia |
|---|---|---|
| Sin cabana → deshabilitado + "Elegi primero una cabana" | `CalendarioRango` (rama `idCabana===null`) | UI (smoke 5) |
| Cabana elegida → consulta A26 | `useAction('disponibilidad.cabana', …, {enabled: idCabana!==null && !mesCargado})` | UI (smoke 5) |
| `fecha_in` pasada → no seleccionable | `inicioValido` (reserva: `ymd < hoy` false) | T1 |
| `ocupada`/`bloqueada` → no seleccionable | `esNocheElegible` | T2, T3 |
| `checkout_disponible` → seleccionable | `esNocheElegible` | T4 |
| Rango que cruza ocupada/bloqueada → no confirmable | `validarRango` + `maxFinSeleccionable` (cap) | T6, T7, T8, T9 |
| Cruce de mes sin cargar → no aprobable | `validarRango` → `falta_cargar`; cap frena en frontera | T10, T11 |
| `payload_invalido` por `fecha_in_pasada` → mensaje UX claro | `textoErrorReserva` | revisar banner (smoke 5) |

### A08 (bloqueo) — **asimetrico, no es igual a A07**
| Criterio | Cubierto por | Evidencia |
|---|---|---|
| Sin cabana → deshabilitado + mensaje | `CalendarioRango` | UI (smoke 5) |
| Cabana elegida → consulta A26 | `useAction` | UI (smoke 5) |
| `fecha_desde` pasada **permitida** | `inicioValido` (bloqueo: sin chequeo de pasado) | T12, y T16 (mismo dia NO vale en reserva) |
| `fecha_hasta <= hoyAR` **no permitida** | `validarRango` (bloqueo: `hasta < manana` → `fecha_hasta_pasada`) + espejo en `validar()` | T13 |
| `fecha_hasta = manana` con desde pasada → ok | `validarRango` | T14 |
| `fecha_hasta > fecha_desde` | `validarRango` (`rango_invertido`) | T15 |
| `ocupada`/`bloqueada` no elegible | `esNocheElegible` | T2, T3 (mismo motor) |
| `checkout_disponible` elegible | `esNocheElegible` | T4 |
| `payload_invalido` por `rango_pasado` → mensaje UX claro | `textoErrorBloqueo` | revisar banner (smoke 5) |

---

## 4. Ejecucion (en TU clon)

```bash
# 1) Crear los 3 archivos nuevos con el contenido entregado:
#    src/lib/fecha.ts
#    src/lib/disponibilidad.ts
#    src/ui/CalendarioRango.tsx

# 2) Aplicar los 3 diffs localizados (anclas exactas en el mensaje):
#    src/lib/contratos.ts        (append de tipos A26)
#    src/screens/CrearReserva.tsx (5 anclas)
#    src/screens/CrearBloqueo.tsx (5 anclas)

cd Apps/portal-operativo
npm install            # sin cambios de lockfile esperados
npx tsc --noEmit --strict   # EXIT 0 esperado
npm run build               # EXIT 0 esperado
git diff --stat -- package.json package-lock.json   # debe estar VACIO

# 3) Commit + push a la rama TEST -> Vercel despliega el preview/TEST.
```

**Anti-OPS:** este paquete es 100% frontend TEST; no toca Supabase/n8n/OPS. No requiere guard de credenciales.

---

## 5. Smoke UI en Vercel (lo que el harness no puede ver)

A07 (Crear reserva) y A08 (Crear bloqueo):

1. **Sin cabana:** el bloque del calendario muestra "Elegi primero una cabana…" y no hay grilla. ✔/✘
2. **Elegis cabana:** aparece la grilla del mes; al navegar meses se cargan dias (spinner breve "Cargando disponibilidad…"). ✔/✘
3. **Colores/leyenda:** ocupada en verde, bloqueada en gris, libre en blanco; `checkout_disponible` con marca "sale"; leyenda visible. ✔/✘
4. **Seleccion A07:** un dia pasado / ocupado / bloqueado no es clickeable; `checkout_disponible` si; al fijar check-in, los dias mas alla de la primera noche ocupada quedan deshabilitados (no podes cruzar). ✔/✘
5. **Cambio de cabana** con fechas ya elegidas → se limpia la seleccion. ✔/✘
6. **A08 asimetrico:** podes elegir `fecha_desde` en el pasado; pero no podes fijar `fecha_hasta <= hoy` (queda fuera de lo seleccionable / cae el aviso). ✔/✘
7. **Mensajes de backend (si llegan):** forzando el caso, el banner muestra el texto UX de `fecha_in_pasada` (A07) / `rango_pasado` (A08), no el generico. ✔/✘
8. **Submit:** con rango valido, A07/A08 envian por el flujo existente (`useEnviar`) y se ve la TarjetaExito. ✔/✘
9. **Blindaje anti-stale (carrera de cabana):** elegi cabana A; mientras carga (o inmediatamente despues) cambia a cabana B. Esperado: se limpia la seleccion previa y NO quedan colores/dias de A pintados sobre el calendario de B (la grilla refleja solo a B). ✔/✘

---

## 6. Notas de diseno (para el cierre / satelites despues)

- **Half-open `[desde, hasta)`** identico al backend; `hasta` (checkout/liberacion) no es noche del rango. El cap en la primera noche ocupada habilita back-to-back (salir el dia en que entra el siguiente).
- **Cruce de mes:** la cache acumula por `fecha`; `maxFinSeleccionable` frena en la frontera de lo cargado y `validarRango` exige todas las noches cargadas (`falta_cargar`). Como la seleccion es por click sobre celdas visibles, navegar a un mes lo carga: no se puede aprobar un rango con una noche en un mes sin consultar.
- **Asimetria A07/A08** vive en `inicioValido` (modo) y `validarRango` (regla de `fecha_hasta` solo en bloqueo). No hay regla global "todo pasado disabled".
- **`payload_invalido` sobrecargado** (fecha pasada vs email/otros): se desambigua por token de `message` (`fecha_in_pasada` / `rango_pasado`). El guard preventivo dispara primero; el mensaje de backend es red de seguridad. (Candidato a `P-FE`/`D-FE` en el cierre.)
- **horas A26** (`hora_checkin_base`/`hora_checkout_base`) llegan por contrato pero NO se usan en este bloque (sin recambio ni validacion horaria, como pediste).
- **Blindaje anti-respuesta-stale (carrera de cabana A->B):** ademas de la cache atada a la cabana, el `useEffect` de fusion descarta una respuesta COMPLETA si `idCabana === null` o si algun `d.id_cabana !== idCabana` (sin fusion parcial). Es seguro porque se verifico en `obtener_disponibilidad_rango` que el SELECT devuelve `m.id_cabana` (de `cabanas_activas CROSS JOIN dias`) en CADA noche, libres incluidas: nunca `null` para una cabana valida. El `number | null` del contrato es solo la fila de padding de cabana invalida/inactiva, que sale por `no_encontrado` y nunca como `dia`. Por eso la regla literal no descarta la respuesta legitima de la cabana actual.
