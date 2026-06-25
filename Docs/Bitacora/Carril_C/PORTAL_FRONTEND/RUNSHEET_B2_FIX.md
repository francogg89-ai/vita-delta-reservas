# RUNSHEET — Fix B2 (`useEnviar`: ref `montado` roto bajo React.StrictMode)

**Carril:** C — Portal Operativo Interno (frontend). **Entorno:** TEST. **Cero backend / n8n / OPS / canónico.**
**Qué corrige:** el síntoma reportado en B2 — A08 crea el bloqueo en TEST (visible en A04) pero la UI **no muestra tarjeta de éxito ni banner de conflicto y el botón queda en spinner** (`enviando` retenido).

---

## 1. Diagnóstico (causa raíz)

**No es backend, ni el wrapper A08, ni `callPortal`, ni el gateway.** Es un bug del frontend en `useEnviar` (introducido en B1), que solo se manifiesta en **dev bajo `React.StrictMode`** (lo confirma `main.tsx`, que envuelve `<App/>` en `<StrictMode>`).

- `useEnviar` usaba un **ref persistente** `const montado = useRef(true)` con un efecto de **cuerpo vacío** que solo devolvía cleanup: `useEffect(() => () => { montado.current = false; }, [])`.
- En dev, StrictMode hace **montar → cleanup → montar** y dispara los efectos dos veces. Secuencia: efecto (cuerpo vacío) → cleanup (`montado.current=false`) → efecto otra vez (cuerpo vacío, **no lo vuelve a poner en true**). Queda `montado.current === false` **para siempre**, con el componente montado.
- Consecuencia en `enviar`, cuando `callPortal` resuelve OK:
  - `if (!montado.current) return;` → como `montado.current===false`, **retorna y se saltea `setResultado(data)`** (se descarta el resultado).
  - `finally { enviandoRef.current = false; if (montado.current) setEnviando(false); }` → `if (false)` → **`setEnviando(false)` nunca corre → spinner eterno**, sin tarjeta ni banner.
- Por qué las **lecturas** (`useAction`) no sufren esto: usan un flag **local por corrida** (`let activo = true` dentro del efecto), que es StrictMode-safe (cada corrida arranca en true). Por eso el sub-slice 1 funcionaba y esto recién aparece en la **primera escritura**.

**Predicción falsable (DevTools → Network):** la request a `portal-api` figura **200 Completed** con el envelope válido en el body (no Pending). La respuesta llega; el frontend la descartaba.

## 2. El fix (mínimo, 1 archivo)

`src/hooks/useEnviar.ts` — el efecto ahora **re-setea `montado.current = true` al (re)montar**, patrón estándar StrictMode-safe:

```ts
useEffect(() => {
  montado.current = true;
  return () => { montado.current = false; };
}, []);
```

Con esto, bajo StrictMode: render (ref true) → efecto (true) → cleanup (false) → efecto (true) → montado con `true`. En desmontaje real → cleanup (false). El guard sigue cumpliendo su función (no setear estado en un componente realmente desmontado, p. ej. si una acción de éxito navega fuera), sin romper el caso normal.

**Único archivo tocado.** No cambia nada de A08/CrearBloqueo, rutas, callPortal, gateway ni wrappers.

## 3. Cómo aplicar

```
# desde la raíz del repo
tar -xzf portal-operativo-b2-fix-useEnviar.tar.gz   # reemplaza src/hooks/useEnviar.ts
cd Apps/portal-operativo
npm run typecheck   # EXIT 0
npm run build       # EXIT 0
```
**Mi corrida:** typecheck EXIT 0; build EXIT 0, `✓ 115 modules` (igual que B2: es un cambio de una línea en un archivo ya presente).

## 4. Re-test de B2 (lo que debería pasar ahora)

Corré la app en dev (`npm run dev`, StrictMode activo) y repetí el flujo A08 con vicky/socio:

| Caso | Esperado tras el fix |
|---|---|
| Alta OK | **Tarjeta verde "Bloqueo creado #id"** (cabaña + tipo) + acciones; el spinner se apaga |
| Mismo rango otra vez (solapa) | **Banner ámbar "Se solapa con una reserva, pre-reserva o bloqueo en ese rango."**; spinner apagado |
| `payload_invalido` (datos rechazados) | banner rojo con el `message`; spinner apagado |
| Doble-click | un solo request; el botón vuelve a su estado al terminar |
| `estado_incierto` (si ocurre) | banner con **Ver calendario operativo** principal + Reintentar secundario |

El resto de la matriz por rol de `RUNSHEET_B2.md` sigue vigente (jenny no ve el ítem ni entra por URL).

## 5. Lección propuesta (para formalizar al CIERRE del sub-slice 2, no ahora)

- **L-FE-03 (candidata):** el patrón "mounted ref" (`useRef(true)` + efecto que solo limpia) **se rompe bajo `React.StrictMode` en dev**: el doble-invoke deja el ref en `false` permanentemente porque el cuerpo del efecto no lo re-setea en true. El fix es setear `ref.current = true` en el cuerpo del efecto. Alternativa válida: flag local por corrida del efecto (lo que ya hace `useAction`). Se propaga a `Lecciones_Aprendidas.md` (CRLF) recién en la propagación coordinada del cierre.

## 6. Estado

- **B2 NO se cierra todavía:** queda pendiente tu re-test contra TEST con este fix.
- Cuando confirmes que aparecen tarjeta de éxito y banner de conflicto y el spinner se apaga, **B2 cierra** y sigo con **B3 — A07 `reserva.crear_manual`**.
