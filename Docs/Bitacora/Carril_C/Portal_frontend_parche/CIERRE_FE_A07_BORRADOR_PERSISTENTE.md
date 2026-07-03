# CIERRE FINAL — A07: Borrador persistente de formularios (Frontend TEST)

**Estado:** ✅ Frente completo, validado en TEST — smoke manual en celular, verde operativo (2026-07-03). Frontend-only; sin cambios de backend ni de contrato.
**Entorno:** TEST.
**Ubicación en el repo:** `Apps/portal-operativo/` (Vite app).
**Archivos finales tocados:**
- `Apps/portal-operativo/src/hooks/useBorradorPersistente.ts` (nuevo)
- `Apps/portal-operativo/src/screens/CrearReserva.tsx` (A07)
- `Apps/portal-operativo/src/ui/CalendarioRango.tsx`
- `Apps/portal-operativo/src/auth/AuthProvider.tsx`
- `Docs/Implementacion/Carril_C/Frontend/CIERRE_FE_A07_BORRADOR_PERSISTENTE.md` (este documento)

**Autores:** Franco (titular; ejecutó git/Vercel y validó en celular) + Claude (diseñó/validó/generó los artefactos como entregable de repo; sin ejecutar sobre el repo ni el entorno — la regla de ejecución queda intacta).
**Decisiones propuestas:** D-FE-35, D-FE-36 (+ enmienda a D-FE-35). **Lecciones propuestas:** L-FE-10, L-FE-11, L-FE-12.

---

## 1. Contexto del problema

Al cargar una reserva en A07 (Crear reserva) y salir de la pantalla —navegar a otra sección del portal, o cambiar de app en el celular para buscar un dato del huésped— y volver, el formulario aparecía vacío: había que recargar nombre, teléfono, fechas y todo de nuevo. Dolor operativo y cotidiano, sobre todo en celular.

## 2. Causa técnica

- A07 mantenía el estado del formulario con `useState(INICIAL)`, en memoria. Cuando la pantalla se desmonta y remonta —navegación interna del portal (`AppShell` sobrevive al cambio de ruta, pero la pantalla no), remonte del árbol por auth, o recarga por descarte de la pestaña en el celular— `useState` vuelve a `INICIAL` y se pierde lo tipeado.
- Ya con la persistencia del form, `CalendarioRango` seguía limpiando `fecha_in`/`fecha_out` en el primer montaje: su `useEffect(..., [idCabana])` corría también al montar y, al ver `desde || hasta` ya restaurados, llamaba `onChange('', '')`, borrando las fechas recién restauradas.
- Los borradores locales podían sobrevivir al cierre de sesión: sin un barrido explícito, en un dispositivo compartido quedaban datos de huésped tras hacer "Salir" (o tras un corte de sesión por `no_autorizado`).

## 3. Solución aplicada

**Persistencia del borrador (hook + A07).**
- Hook reutilizable `useBorradorPersistente` sobre `sessionStorage` (nativo, sin dependencias): restaura al montar (lazy init con merge sobre el inicial), guarda en cada cambio, y **no** limpia al desmontar (para que la navegación interna conserve el borrador).
- `sessionStorage`, **no** `localStorage`: sobrevive a la recarga/descarte de la misma pestaña y se borra al cerrarla → mínimo residuo de datos personales del huésped.
- Clave versionada y por ambiente: `vd:${AMBIENTE}:draft:${id}`. ID/versión de A07: `a07-crear-reserva:v1` (un cambio de forma del form se resuelve bumpeando `:vN`).
- TTL de 24 h: un borrador más viejo se descarta al restaurar.
- Persistencia **solo del `form`**: nunca auth, JWT, sesión, errores, resultado ni estado incierto.
- Limpieza del borrador en el **éxito** de creación de reserva y en el botón **"Crear otra"**.

**Selección del calendario.**
- `CalendarioRango` distingue **primer montaje vs cambio real de cabaña** con un `useRef` de la cabaña previa: el efecto `[idCabana]` saltea el primer montaje (early-return) y solo reinicia selección + cache ante un cambio real de cabaña (la disponibilidad es por cabaña). Seguro sin colaterales porque `visibleYm` y `cacheState` ya se inicializan en su `useState` con los mismos valores que el efecto seteaba al montar.

**Higiene de sesión.**
- `AuthProvider` llama `limpiarBorradores()` en el logout explícito (antes de `signOut()`, robusto a cambios futuros del listener) y en la rama `SIGNED_OUT` del `onAuthStateChange` (cubre también el corte por `no_autorizado` de `cargarContexto`). El barrido es idempotente y acotado por prefijo `vd:${AMBIENTE}:draft:`; no toca el storage de auth.

## 4. Validación

- `npm run typecheck` → EXIT 0.
- `npm run build` → EXIT 0.
- Smoke manual en celular (TEST): verde en los cinco puntos.
  1. A07 → cargar datos + fechas → ir a otra pantalla del portal → volver → conserva todo.
  2. A07 → cargar datos + fechas → cambiar de app → volver → conserva todo.
  3. Cambiar de cabaña → limpia fechas (correcto).
  4. Crear reserva con éxito → limpia el formulario.
  5. Cargar datos sin crear reserva → "Salir" → volver a loguear → A07 vacío.

## 5. Alcance negativo (lo que NO se tocó)

- No backend.
- No Supabase.
- No n8n.
- No gateway.
- No wrappers.
- No A26.
- No se persiste disponibilidad como fuente de verdad: el calendario sigue consultando A26 por mes visible; solo se conserva la **selección** del usuario, que ya vivía en frontend. Principio #6 intacto (el front no calcula nada crítico).
- No hay cambios de contrato API (la interfaz `Props` de `CalendarioRango` no se modifica; catálogo del gateway sin tocar). Sin dependencias nuevas.

## 6. Decisiones propuestas

- **D-FE-35 — Borrador persistente de formularios multi-campo en `sessionStorage`.** Vía `useBorradorPersistente`: clave versionada y por ambiente (`vd:${AMBIENTE}:draft:<id>`), restaura al montar, guarda en cada cambio, no limpia al desmontar, TTL 24 h. Solo persiste el `form` (nunca auth/JWT/errores/resultado). Limpia en éxito y en "Crear otra". Cableado en A07 (`a07-crear-reserva:v1`); hook reutilizable para A08/A10/A11. `sessionStorage`, no `localStorage`, para minimizar residuo de PII.
- **D-FE-36 — El calendario de rango no limpia la selección en el primer montaje; solo ante un cambio real de cabaña.** El efecto `[idCabana]` de `CalendarioRango` saltea el montaje vía `useRef` de la cabaña previa y solo reinicia selección + cache ante un cambio real de cabaña. Preserva `fecha_in`/`fecha_out` restaurados del borrador; sin tocar A26 ni el contrato.
- **Enmienda a D-FE-35 — `limpiarBorradores()` cableado al cierre de sesión.** La función de barrido (ya prevista en el diseño del hook) queda conectada en `AuthProvider`: en el logout explícito (antes de `signOut()`) y en la rama `SIGNED_OUT` del listener. Cubre el logout de usuario y el corte por `no_autorizado`. Idempotente y acotado por prefijo `vd:${AMBIENTE}:draft:`.

## 7. Lecciones propuestas

- **L-FE-10 — El "form vacío al volver" puede venir de navegación interna, remonte de árbol/auth o descarte móvil.** El fix correcto es persistir el borrador con independencia de la causa, no diagnosticar una sola. (Corolario: el hook no debe limpiar al desmontar, o borraría el borrador justo en la navegación interna.)
- **L-FE-11 — Los efectos de "reset ante cambio de X" deben distinguir primer montaje de cambio real cuando hay restauración de estado.** Se resuelve con un `useRef` del valor previo; si no, machacan props/estado restaurados. Conviene verificar además que lo que el efecto seteaba al montar ya lo cubra el `useState` inicial, para poder saltarlo sin regresión.
- **L-FE-12 — Los datos locales sensibles deben limpiarse en todas las salidas de sesión, no solo en el botón "Salir".** Además del logout explícito hay cortes que no pasan por el botón (acá, `no_autorizado` → `signOut`), que solo cubre la rama `SIGNED_OUT`. Regla: limpiar antes del `signOut` en el handler explícito (robusto a cambios del listener) **y** en `SIGNED_OUT` (captura los cortes); es seguro porque el barrido es idempotente y acotado por prefijo.

> Numeración **propuesta**, pendiente de canonización formal contra los satélites (`DECISIONES_NO_REABRIR.md` / `Lecciones_Aprendidas.md`). El repo está en D-FE-30 / L-FE-09; D-FE-31…34 quedan pendientes de canonizar. Confirmar los números al mintear.

## 8. Nota operativa — herramientas temporales

Los patchers `patch_borrador_a07.py`, `patch_calendario_seleccion.py` y `patch_logout_barrido_borradores.py` fueron **herramientas temporales de aplicación** de los diffs; **no forman parte del producto**. No deben quedar en la raíz del repo ni commitearse: eliminarlos antes del commit.
