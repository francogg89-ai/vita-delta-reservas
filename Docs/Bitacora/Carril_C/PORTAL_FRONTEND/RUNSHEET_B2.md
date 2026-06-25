# RUNSHEET — Sub-slice 2 / Bloque B2 (A08 `bloqueo.crear_manual`)

**Carril:** C — Portal Operativo Interno (frontend). **Entorno:** TEST. **Cero backend / n8n / OPS / canónico.**
**Base:** B1 (cimientos) aplicado. **Incluye el patch mínimo de B1** acordado (`setResultado(null)` al inicio de `enviar`).
**Alcance B2:** la **primera pantalla de escritura** — A08 crear bloqueo (sin `idempotency_key`; guard por solapamiento). Consume los cimientos de B1 y se cablea en el router reemplazando su `PlaceholderView`.

---

## 1. Qué incluye B2 (3 archivos)

- `src/hooks/useEnviar.ts` — **modificado (patch B1):** `enviar` ahora también limpia `resultado` al iniciar (no queda una tarjeta de éxito vieja durante un submit nuevo). Reemplaza el `useEnviar.ts` de B1.
- `src/screens/CrearBloqueo.tsx` — **nuevo (A08).** Formulario + estados de envío/éxito/error/incierto.
- `src/app/rutas.tsx` — **modificado:** import de `CrearBloqueo` + entrada `'bloqueo.crear_manual': CrearBloqueo` en `PANTALLAS` (la ruta `/bloqueos/crear` ya estaba en `ACTION_REGISTRY`; ahora deja de ser placeholder). Comentario del mapa actualizado.

No se toca ningún otro archivo.

## 2. Formulario A08 (campos, espejo del validador del gateway, D-FE-23)

| Campo UI | input | → payload | req | validación cliente |
|---|---|---|---|---|
| Cabaña | select `CABANAS_TEST` | `id_cabana` (number) | **sí** (sin "todas"; bloqueo total no se expone, 8D) | una cabaña elegida |
| Desde | `date` | `fecha_desde` | sí | presente |
| Hasta (liberación) | `date` | `fecha_hasta` | sí | presente y **> desde** |
| Motivo | select `MOTIVOS_BLOQUEO` | `motivo` | sí | enum elegido |
| Descripción | `textarea` | `descripcion` (se omite si vacía) | no | — |

Sin `idempotency_key` → `useEnviar('bloqueo.crear_manual','none')`. La disponibilidad real (solapamiento) la valida el backend; el cliente no la replica.

## 3. UX de resultado

- **Éxito** (`{ id_bloqueo, id_cabana, tipo_bloqueo }`): tarjeta verde "Bloqueo creado #id" + cabaña + tipo; acciones **Ver calendario operativo** (`/calendarios/operativo`) y **Crear otro** (`reset()` + limpia el form).
- **`conflicto`** (solapa reserva/pre-reserva/bloqueo): banner ámbar "Se solapa con una reserva, pre-reserva o bloqueo en ese rango."
- **`payload_invalido`**: banner rojo con el `message` del backend.
- **`estado_incierto`** (D-FE-22, ajuste aprobado): banner ámbar "No se pudo confirmar el bloqueo." con acción **principal = Ver calendario operativo** y **secundaria = Reintentar**, con el aviso explícito: *"Si ya se creó, reintentar puede volver como conflicto: primero verificá el calendario."* El flujo correcto del operador es incierto → abrir A04 → verificar.
- **Anti-doble-click:** el botón se deshabilita y muestra spinner mientras hay un envío; `useEnviar` además ignora envíos en vuelo.

## 4. Cómo aplicar

```
# desde la raíz del repo (vita-delta-reservas/)
tar -xzf portal-operativo-b2-a08-bloqueo.tar.gz   # reemplaza useEnviar.ts + rutas.tsx, agrega CrearBloqueo.tsx
cd Apps/portal-operativo
npm run typecheck   # EXIT 0
npm run build       # EXIT 0
```
Sin dependencias nuevas. **Mi corrida:** typecheck EXIT 0; build EXIT 0, `✓ 115 modules transformed` (eran 107 en B1: +8 = la pantalla A08 + los cimientos de B1 que ahora entran al bundle al estar cableados).

## 5. Matriz de prueba por rol (corré la app en local contra TEST)

| Caso | jenny | vicky | socio |
|---|---|---|---|
| Ítem "Crear bloqueo" en el menú (grupo Bloqueos) | **no aparece** | sí | sí |
| Navegación directa por URL a `/bloqueos/crear` | redirect `/` + aviso ámbar (RutaProtegida); si se saltara, gateway `rol_no_permitido` | entra al form | entra al form |
| Validación: falta cabaña / fechas / motivo → error inline; `hasta ≤ desde` → error | — | sí | sí |
| Alta OK → tarjeta "Bloqueo creado #id" (cabaña + tipo); "Ver calendario operativo" navega; "Crear otro" limpia | — | sí | sí |
| Solapamiento (rango que pisa una reserva/pre-reserva/bloqueo de TEST) → banner `conflicto` | — | sí | sí |
| Doble-click rápido en "Crear bloqueo" → un solo request (spinner + disabled) | — | sí | sí |

**Notas de prueba:**
- El `conflicto` se prueba creando un bloqueo sobre un rango que pise algo existente en TEST.
- `estado_incierto` no se fuerza fácil desde la UI (es el camino no-confiable del dispatch: timeout/red, igual que en los smokes de backend). En TEST normal no se dispara; la UX queda verificable por inspección y se activa sola si el gateway devuelve `estado_incierto`.
- Mobile-first: una columna en celular; las dos fechas en grilla de 2 columnas desde `sm`. Sin localStorage/sessionStorage.

## 6. Próximo: B3 — A07 `reserva.crear_manual`

El form grande (sin key, idempotencia derivada por el wrapper → `idempotent_match`), con el selector único "Medio de pago" que llena `canal_pago_esperado` + `medio_pago`, contacto del huésped (teléfono **o** email), y companions A24/A05/A04 ante `estado_incierto`.
