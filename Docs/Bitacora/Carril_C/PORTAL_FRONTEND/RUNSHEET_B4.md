# RUNSHEET — Sub-slice 2 / Bloque B4 (A11 `cargar.gasto_interno`)

**Carril:** C — Portal Operativo Interno (frontend). **Entorno:** TEST. **Cero backend / n8n / OPS / canónico.**
**Base:** B1 (cimientos) + B2 (A08) + B3 (A07), todos cerrados.
**Alcance B4:** A11 cargar gasto interno — el form con más condicionales (clases A/C/D/E). **Key SIBLING** (la idempotency_key viaja top-level, no en payload). Se cablea en el router reemplazando su `PlaceholderView`.

---

## 1. Qué incluye B4 (2 archivos)

- `src/screens/CargarGasto.tsx` — **nuevo (A11).**
- `src/app/rutas.tsx` — **modificado:** import + entrada `'cargar.gasto_interno': CargarGasto` en `PANTALLAS`. Ruta `/economico/cargar-gasto` ya estaba en `ACTION_REGISTRY`.

No se toca ningún otro archivo.

## 2. Formulario A11 (campos, espejo de las 14 constraints de `gastos_internos`, D-FE-23)

*Gasto*
| Campo UI | input | → payload | req | regla |
|---|---|---|---|---|
| Fecha | `date` (default **hoy**) | `fecha` | sí | presente. `periodo` **no se expone** (la función = día 1 del mes de `fecha`) |
| Clase | select `CLASES_GASTO` (default **vacío**) | `clase` | sí | A/C/D/E |
| Zona | select `ZONAS_TEST` | `id_zona` | sí **si D** | aparece **solo clase D** |
| Cabaña | select `CABANAS_TEST` | `id_cabana` | sí **si E** | aparece **solo clase E** |
| Etiqueta | `text` | `etiqueta` | sí | no vacía. `'horas de trabajo'` ⇒ pagador socio |
| Monto | `number` | `monto` | sí | **> 0**. Moneda ARS fija (no se expone) |

*Pago*
| Campo UI | input | → payload | req | regla |
|---|---|---|---|---|
| Pagador | select `PAGADORES_GASTO` (default **Caja**) | `pagador_tipo` | sí | caja / socio |
| Socio | select `SOCIOS_TEST` | `id_socio_pagador` | sí **si socio** | aparece **solo pagador=socio** |
| Medio de pago | `text` | `medio_pago` | no | si vacío se omite |

*Detalle*
| Campo UI | input | → payload | req | regla |
|---|---|---|---|---|
| Comentario | `textarea` | `comentario` | **sí** | obligatorio siempre (omitimos `clase_sugerida`) |
| Comprobante (URL) | `url` | `comprobante_url` | no | link externo; sin upload de archivos |

**Coherencia por construcción:** el payload incluye `id_zona` **solo en D**, `id_cabana` **solo en E**, `id_socio_pagador` **solo en socio**. Aunque el estado tenga un valor viejo al cambiar de clase/pagador, no se manda (evita violar `chk_..._alcance_por_clase` / `chk_..._pagador_consistente`).

**Key:** `useEnviar('cargar.gasto_interno','sibling')` → la idempotency_key viaja **top-level** (el validador rechaza claves de control en el payload). Respuesta `{ id_gasto, idempotente }`.

## 3. Pre-validación (espejo de las constraints; P-FE-07: el `detail.constraint` no llega, el fallback es el `message` genérico del backend)

`fecha` req · `clase` req · (D⇒`id_zona` req / E⇒`id_cabana` req) · `etiqueta` no vacía · `monto`>0 · `pagador_tipo` req · (socio⇒`id_socio_pagador` req) · `comentario` req · (`etiqueta`=='horas de trabajo' ⇒ pagador socio).

## 4. UX de resultado

- **Éxito** (`{ id_gasto, idempotente }`): tarjeta "Gasto cargado #id"; si `idempotente:true` → "ya estaba cargado: no se duplicó". Acciones **Ver gastos** (`/economico/gastos`, A13) y **Cargar otro** (`reset()`, key nueva).
- **`payload_invalido`**: banner rojo con el `message` del backend (genérico para coherencias).
- **`conflicto`** (idempotencia: nonce_replay / payload_mismatch / actor_mismatch): banner ámbar "Hubo un conflicto de idempotencia. Cargá el gasto de nuevo." → el reset genera key nueva.
- **`estado_incierto`** (D-FE-22): banner con **Ver gastos** principal + **Reintentar** secundario (reusa la **misma** key; si ya se cargó vuelve `idempotente:true`).
- **Anti-doble-click:** botón con spinner + `useEnviar` ignora envíos en vuelo.

> **Idempotencia de A11 (≠ A07):** A11 dedupea por **nonce** (la key), no por contenido. Reintentar tras `estado_incierto` reusa la key → `idempotente:true`. Pero **"Cargar otro" con datos idénticos crea un gasto NUEVO** (dos gastos reales con misma etiqueta/monto son válidos). El `idempotente:true` solo aparece en el reintento con la misma key / reintento de red.

## 5. Cómo aplicar

```
# desde la raíz del repo
tar -xzf portal-operativo-b4-a11-gasto.tar.gz   # agrega CargarGasto.tsx, reemplaza rutas.tsx
cd Apps/portal-operativo
npm run typecheck   # EXIT 0
npm run build       # EXIT 0
```
**Mi corrida:** typecheck EXIT 0; build EXIT 0, `✓ 117 modules` (eran 116: +1 = la pantalla A11; reusa los cimientos).

## 6. Matriz de prueba por rol (app en dev contra TEST)

| Caso | jenny | vicky | socio |
|---|---|---|---|
| Ítem "Cargar gasto" en el menú (grupo Económico) | **no aparece** | sí | sí |
| Navegación directa a `/economico/cargar-gasto` | redirect `/` + aviso; si se saltara, gateway `rol_no_permitido` | entra | entra |
| Validación: falta fecha/clase/etiqueta/monto/comentario; D sin zona; E sin cabaña; socio sin socio; monto ≤ 0 | — | sí | sí |
| **Clase A** (Común todos) → no muestra zona ni cabaña → carga OK | — | sí | sí |
| **Clase C** (Común operativo) → idem → carga OK | — | sí | sí |
| **Clase D** (por zona) → muestra Zona (req) → carga OK con `id_zona` | — | sí | sí |
| **Clase E** (por cabaña) → muestra Cabaña (req) → carga OK con `id_cabana` | — | sí | sí |
| **Pagador Caja** → no muestra socio → carga OK (`id_socio_pagador` null) | — | sí | sí |
| **Pagador Socio** → muestra Socio (req) → carga OK con `id_socio_pagador` | — | sí | sí |
| **Etiqueta 'horas de trabajo' + pagador Caja** → error inline, **sin request** | — | sí | sí |
| **Etiqueta 'horas de trabajo' + pagador Socio** → carga OK | — | sí | sí |
| Cambiar de clase D→E (o socio→caja) y enviar → payload coherente (no manda el id viejo) | — | sí | sí |
| Doble-click en "Cargar gasto" → un solo request | — | sí | sí |

**Notas:**
- La capacidad/medio/comprobante no tienen enum: medio y comprobante son **texto libre opcional** (si vacíos, se omiten).
- `idempotente:true` se prueba forzando `estado_incierto` y dándole **Reintentar** (reusa la key). Un alta normal trae `idempotente:false` (sin nota). Una re-carga vía "Cargar otro" es un gasto nuevo.
- Mobile-first: secciones Gasto/Pago/Detalle; una columna en celular, grillas de 2 en `sm`. Sin localStorage/sessionStorage.

## 7. Próximo: B5 — A10 `cobranza.registrar_saldo` (último bloque de escrituras)

Key **en payload**, **bloqueo duro anti-sobrepago** (D-FE-21: mostrar saldo vivo, deshabilitar submit si monto > saldo o saldo ≤ 0, re-render `saldo_real_actual` al éxito, reconsultar A05/A12 ante conflicto), companion A12/A05. **Además en B5:** el deep-link A12→A10 por `?id_reserva=` y el read de `?id_reserva` en A05 (el "Ver detalle" diferido de B3).
