# CIERRE — A07: Borrador persistente + selección de calendario (Frontend TEST)

**Estado:** ✅ Validado en TEST — smoke manual en celular, verde operativo (2026-07-02). Frontend-only; sin cambios de backend ni de contrato.
**Entorno:** TEST.
**Ubicación en el repo:** `Apps/portal-operativo/` (Vite app).
**Archivos modificados:**
- `Apps/portal-operativo/src/hooks/useBorradorPersistente.ts` (nuevo)
- `Apps/portal-operativo/src/screens/CrearReserva.tsx` (A07)
- `Apps/portal-operativo/src/ui/CalendarioRango.tsx`

**Autores:** Franco (titular; ejecutó git/Vercel y validó en celular) + Claude (diseñó/validó/generó los artefactos como entregable de repo; sin ejecutar sobre el repo ni el entorno — la regla de ejecución queda intacta).
**Decisiones propuestas:** D-FE-35, D-FE-36. **Lecciones propuestas:** L-FE-10, L-FE-11.

---

## 1. Contexto del problema

Al cargar una reserva en A07 (Crear reserva) y salir de la pantalla —navegar a otra sección del portal, o cambiar de app en el celular para buscar un dato del huésped— y volver, el formulario aparecía vacío: había que recargar nombre, teléfono, fechas y todo de nuevo. Dolor operativo y cotidiano, sobre todo en celular.

## 2. Causa técnica

- A07 mantenía el estado del formulario con `useState(INICIAL)`, en memoria. Cuando la pantalla se desmonta y remonta —navegación interna del portal (`AppShell` sobrevive al cambio de ruta, pero la pantalla no), remonte del árbol por auth, o recarga por descarte de la pestaña en el celular— `useState` vuelve a `INICIAL` y se pierde lo tipeado.
- Ya con la persistencia del form, apareció un segundo borde: `CalendarioRango` limpiaba `fecha_in`/`fecha_out` en el primer montaje. Su `useEffect(..., [idCabana])` corría también al montar y, al ver `desde || hasta` ya restaurados, llamaba `onChange('', '')`, borrando las fechas recién restauradas.

## 3. Solución aplicada

- Hook reutilizable `useBorradorPersistente` sobre `sessionStorage` (nativo, sin dependencias): restaura al montar (lazy init con merge sobre el inicial), guarda en cada cambio, y **no** limpia al desmontar (para que la navegación interna conserve el borrador). Clave versionada y por ambiente: `vd:${AMBIENTE}:draft:a07-crear-reserva:v1`. TTL de 24 h (un borrador más viejo se descarta al restaurar).
- Persistencia **solo del `form`**: nunca auth, JWT, sesión, errores, resultado ni estado incierto.
- Limpieza del borrador en el **éxito** de creación de reserva y en el botón **"Crear otra"**.
- `CalendarioRango` distingue **primer montaje vs cambio real de cabaña** con un `useRef` de la cabaña previa: el efecto `[idCabana]` saltea el primer montaje (early-return) y solo reinicia selección + cache ante un cambio real de cabaña (la disponibilidad es por cabaña). Seguro sin colaterales porque `visibleYm` y `cacheState` ya se inicializan en su `useState` con los mismos valores que el efecto seteaba al montar.
- `sessionStorage` (no `localStorage`): sobrevive a la recarga/descarte de la misma pestaña y se borra al cerrarla → mínimo residuo de datos personales del huésped.

## 4. Validación

- `npm run typecheck` → EXIT 0.
- `npm run build` → EXIT 0.
- Smoke manual en celular (TEST): verde.
  - A07 conserva los datos al navegar a otra pantalla del portal y volver.
  - A07 conserva los datos al cambiar de app y volver.
  - `fecha_in`/`fecha_out` se conservan al remontar A07.
  - Cambio manual de cabaña → el calendario limpia fechas (correcto).
  - Reserva creada con éxito → borrador completo limpio.

## 5. Alcance negativo (lo que NO se tocó)

- No backend.
- No Supabase.
- No n8n.
- No gateway ni wrappers.
- No A26.
- No se persiste disponibilidad como fuente de verdad: el calendario sigue consultando A26 por mes visible; solo se conserva la **selección** del usuario, que ya vivía en frontend. Principio #6 intacto (el front no calcula nada crítico).
- Sin dependencias nuevas; contrato sin cambios (la interfaz `Props` de `CalendarioRango` no se modifica; catálogo del gateway sin tocar).

## 6. Decisiones propuestas

- **D-FE-35 — Borrador persistente de formularios multi-campo en `sessionStorage`.** Vía `useBorradorPersistente`: clave versionada y por ambiente (`vd:${AMBIENTE}:draft:<id>`), restaura al montar, guarda en cada cambio, no limpia al desmontar, TTL 24 h. Solo persiste el `form` (nunca auth/JWT/errores/resultado). Limpia en éxito y en "Crear otra". Cableado en A07 (`a07-crear-reserva:v1`); hook reutilizable para A08/A10/A11. `sessionStorage`, no `localStorage`, para minimizar residuo de PII. (El hook exporta `limpiarBorradores()` para un futuro barrido en logout, aún sin cablear.)
- **D-FE-36 — El calendario de rango no limpia la selección en el primer montaje; solo ante un cambio real de cabaña.** El efecto `[idCabana]` de `CalendarioRango` saltea el montaje vía `useRef` de la cabaña previa y solo reinicia selección + cache ante un cambio real de cabaña. Preserva `fecha_in`/`fecha_out` restaurados del borrador; sin tocar A26 ni el contrato.

## 7. Lecciones propuestas

- **L-FE-10 — El "form vacío al volver" puede venir de navegación interna, remonte de auth o descarte móvil.** El fix correcto es persistir el borrador con independencia de la causa, no diagnosticar una sola. (Corolario: el hook no debe limpiar al desmontar, o borraría el borrador justo en la navegación interna.)
- **L-FE-11 — Los efectos de "reset ante cambio de X" deben distinguir primer montaje de cambio real cuando existe restauración de estado.** Se resuelve con un `useRef` del valor previo; si no, machacan props/estado restaurados. Verificar además que lo que el efecto seteaba al montar ya lo cubra el `useState` inicial, para poder saltarlo sin regresión.

> Numeración **propuesta**, pendiente de canonización formal contra los satélites (`DECISIONES_NO_REABRIR.md` / `Lecciones_Aprendidas.md`). El repo está en D-FE-30 / L-FE-09; D-FE-31…34 y D-FE-35 / L-FE-10 quedan pendientes de canonizar. Confirmar el número al mintear.

---

## Nota operativa — herramientas temporales

`patch_borrador_a07.py` y `patch_calendario_seleccion.py` fueron **herramientas temporales de aplicación** de los diffs; **no forman parte del producto**. Si quedaron en la raíz del repo, eliminarlos.
