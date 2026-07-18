# GUIA DE COPIA — A07 TEST -> OPS
## `portal-a07-crear-reserva` · Vita Delta Reservas · Motor de Horarios B1.3

> **Objetivo.** Llevar la logica funcional de **A07 OPS** a la misma que **A07 TEST**,
> conservando en OPS unicamente sus valores de ambiente. La correccion manual que
> arreglo la salida incorrecta esta en TEST y **falta en OPS**.
>
> **Division de trabajo.** Yo (Claude) diseño, inspecciono, valido y genero artefactos.
> **Vos ejecutas** en n8n. Esta guia no importa ni modifica nada por su cuenta.

---

## 0. Resumen ejecutivo (leelo antes de tocar nada)

- La diferencia funcional entre TEST y OPS esta **concentrada en 2 nodos Code**:
  **`router1_crear`** y **`router3_confirmar`**.
- El resto de los 24 nodos es **identico en logica**; lo unico que cambia es
  **ambiental** (credenciales, path del webhook, referencia al subworkflow de
  avisos, prefijo de idempotencia) o **cosmetico** (comentarios de cabecera,
  UUID interno de una condicion, posiciones, orden del array).
- **Accion real requerida:** reemplazar el **texto del campo `jsCode`** de esos
  dos nodos en OPS. Nada mas.

### REGLA DE ORO
> **NO copies el nodo entero desde TEST.** Copiar el nodo completo arrastra la
> **credencial de TEST**, el **flavor `__TEST`** y las **referencias con sufijo `1`**,
> y te rompe OPS. **Solo reemplazas el contenido del campo `jsCode`** dentro de los
> dos nodos que ya existen en OPS. Como editas OPS en el lugar, **todos los valores
> ambientales de OPS quedan intactos automaticamente** (no tenes que volver a
> seleccionar credencial, webhook ni subworkflow).

### Diferencia de nombres TEST vs OPS (contexto)
En TEST casi todos los nodos llevan sufijo `1` (`router1_crear1`, `Code: derivar1`,
etc.), artefacto de la duplicacion en n8n. En **OPS los nombres son limpios**
(`router1_crear`, `Code: derivar`). El `jsCode` que te doy mas abajo **ya viene con
las referencias limpias** (estilo OPS), asi que **se pega tal cual en OPS** sin
retoques.

---

## 1. Orden de ejecucion

1. Abri el workflow **`portal-a07-crear-reserva__OPS`** en n8n (instancia OPS).
2. **Paso A** — Reemplazar `jsCode` de **`router1_crear`** (seccion 2.1).
3. **Paso B** — Reemplazar `jsCode` de **`router3_confirmar`** (seccion 2.2).
4. **Guardar** el workflow (sin activarlo todavia si preferis validar antes).
5. **Verificacion** — exportar OPS y correr el verificador (seccion 4).
6. **Pruebas funcionales** — seguir `PLAN_PRUEBAS_A07.md`.

> Los pasos A y B son independientes entre si; el orden A->B es solo por prolijidad.

---

## 2. Nodos con cambio funcional (COPIAR jsCode)

### 2.1. Nodo `router1_crear`

- **Estado actual TEST** (`router1_crear1`): maneja `checkin_pisa_checkout_anterior`
  y `checkout_pisa_checkin_posterior` como **conflictos explicitos** con mensajes
  `gap_checkin` / `gap_checkout`, e incluye `fecha_in_pasada` y
  `override_hora_invalido` en la lista de errores de payload.
- **Estado actual OPS** (`router1_crear`): version anterior. **No** tiene los dos
  handlers de gap; **tampoco** tiene `fecha_in_pasada` ni `override_hora_invalido`
  en `payloadInv` (OPS quedo incluso mas atras que el template del repo). Los dos
  errores de gap caen al bucket **generico** (`payload_invalido` / `estado_incierto`).
- **Accion:** **reemplazar el contenido del campo `jsCode`** por el bloque de abajo.
  **No** toques nada mas del nodo.
- **Campos OPS que deben preservarse:** el nodo no tiene credencial ni referencia de
  ambiente; se pega entero sin residuos. (Igual, editas solo el `jsCode`.)
- **Conexiones que deben quedar (sin cambios):**
  `IF0 seguir -[true]-> PG-1 crear_prereserva -[main]-> router1_crear -[main]-> IF1 seguir`.
- **Riesgo:** bajo. Es codigo puro sin efectos de ambiente. El unico error posible es
  pegar de mas/de menos; copia el bloque completo.
- **Contenido exacto a pegar** (reemplaza TODO el `jsCode`):

```javascript
// router1_crear — lee PG-1. Mapea error o arma pg2_args (con payload2 que INCLUYE id_pre_reserva).
const res = $json.resultado; const D = $('Code: derivar').first().json;
function mapErr(e) {
  const conflicto = ['no_disponible'];
  const payloadInv = ['cabana_no_existe','cabana_inactiva','excede_capacidad','fechas_invalidas',
    'precio_requerido','huesped_nombre_requerido','huesped_contacto_requerido','hora_fuera_de_rango','payload_invalido','fecha_in_pasada','override_hora_invalido'];

  if (e === 'checkin_pisa_checkout_anterior') return {
    ok:false,
    error: {
      code:'conflicto',
      message:'gap_checkin: El check-in queda demasiado cerca del checkout anterior. Elegí un horario de entrada más tarde.',
      detail:null
    }
  };

  if (e === 'checkout_pisa_checkin_posterior') return {
    ok:false,
    error: {
      code:'conflicto',
      message:'gap_checkout: El check-out queda demasiado cerca del check-in posterior. Elegí un horario de salida más temprano.',
      detail:null
    }
  };

  if (conflicto.includes(e)) return { ok:false, error: { code:'conflicto', message:'sin disponibilidad en el rango', detail:null } };
  if (payloadInv.includes(e)) return { ok:false, error: { code:'payload_invalido', message:'datos de reserva rechazados: '+e, detail:null } };
  if (e === 'unique_violation_inesperado') return { ok:false, error: { code:'estado_incierto', message:'estado incierto al crear; verificar antes de reintentar', detail:{ paso:'prereserva', ids_creados:{}, source_event:D.sev, idempotency_key:D.idem } } };
  return { ok:false, error: { code:'error_interno', message:'no se pudo crear la prereserva', detail:null } };
}
if (!res || res.ok !== true) return [{ json: { continuar:false, envelope: mapErr(res ? res.error : null) } }];
const id_pre = res.id_pre_reserva;
// payload2 = base + id_pre_reserva (clave EXACTA del payload de registrar_pago, 6B L4580).
const payload2 = Object.assign({}, D.payload2_base, { id_pre_reserva: id_pre });
const pg2_args = JSON.stringify({ idem: D.idem, id_pre, sev: D.sev, payload2 });
return [{ json: { continuar:true, id_pre, pg2_args } }];
```

- **Verificacion visual posterior:** abri el nodo en OPS y confirma que el `jsCode`:
  1. contiene `gap_checkin` y `gap_checkout`;
  2. en `payloadInv` figuran `fecha_in_pasada` y `override_hora_invalido`;
  3. la referencia dice `$('Code: derivar')` (SIN el `1`).

---

### 2.2. Nodo `router3_confirmar`

- **Estado actual TEST** (`router3_confirmar1`): ademas del exito, del recheck por
  `estado_invalido` + `estado_actual='convertida'` y del conflicto por
  `conflicto_al_confirmar` / `no_disponible`, maneja
  `checkin_pisa_checkout_anterior` y `checkout_pisa_checkin_posterior` como
  **conflictos explicitos** (`gap_checkin` / `gap_checkout`) devolviendo el envelope
  de error correcto.
- **Estado actual OPS** (`router3_confirmar`): version anterior. **No** tiene los dos
  handlers de gap; esos casos caen al **generico** (`estado_incierto`).
- **Accion:** **reemplazar el contenido del campo `jsCode`** por el bloque de abajo.
  **No** toques nada mas del nodo.
- **Campos OPS que deben preservarse:** ninguno especial; el nodo no tiene credencial
  ni referencia de ambiente. La referencia a `router1_crear` en el codigo ya viene
  **limpia** (sin `1`), correcta para OPS.
- **Conexiones que deben quedar (sin cambios):**
  `IF2 seguir -[true]-> PG-3 confirmar_reserva -[main]-> router3_confirmar -[main]-> IF3 recheck`
  y **ademas** `router3_confirmar -[main]-> IF aviso 8C-bis (alta nueva)`.
  (El nodo tiene dos salidas por `main#0`: a `IF3 recheck` y al IF del aviso 8C-bis.
  Ambas deben seguir existiendo.)
- **Riesgo:** bajo. Codigo puro. Cuidar de no alterar las dos conexiones de salida.
- **Contenido exacto a pegar** (reemplaza TODO el `jsCode`):

```javascript
// router3_confirmar — lee PG-3. Exito {ok:true,data}; conflicto; ajuste 3:
// estado_invalido + estado_actual='convertida' -> recheck (PG-4); resto -> estado_incierto.
const res = $json.resultado; const D = $('Code: derivar').first().json;
const id_pre = $('router1_crear').first().json.id_pre;
if (res && res.ok === true) return [{ json: { recheck:false, envelope: { ok:true, data: {
  id_reserva: res.id_reserva, id_pre_reserva: res.id_pre_reserva, id_huesped: res.id_huesped, idempotent_match: false } } } }];

const e = res ? res.error : null;

if (e === 'checkin_pisa_checkout_anterior') return [{
  json: {
    recheck:false,
    envelope: {
      ok:false,
      error: {
        code:'conflicto',
        message:'gap_checkin: El check-in queda demasiado cerca del checkout anterior. Elegí un horario de entrada más tarde.',
        detail:null
      }
    }
  }
}];

if (e === 'checkout_pisa_checkin_posterior') return [{
  json: {
    recheck:false,
    envelope: {
      ok:false,
      error: {
        code:'conflicto',
        message:'gap_checkout: El check-out queda demasiado cerca del check-in posterior. Elegí un horario de salida más temprano.',
        detail:null
      }
    }
  }
}];

if (e === 'estado_invalido' && res && res.estado_actual === 'convertida') return [{ json: { recheck:true } }];
if (e === 'conflicto_al_confirmar' || e === 'no_disponible') return [{ json: { recheck:false, envelope: {
  ok:false, error: { code:'conflicto', message:'conflicto de disponibilidad al confirmar', detail:null } } } }];
return [{ json: { recheck:false, envelope: { ok:false, error: {
  code:'estado_incierto', message:'estado incierto al confirmar; verificar antes de reintentar',
  detail: { paso:'confirmacion', ids_creados: { id_pre_reserva: id_pre }, source_event: D.sev, idempotency_key: D.idem } } } } }];
```

- **Verificacion visual posterior:** abri el nodo en OPS y confirma que el `jsCode`:
  1. contiene `gap_checkin` y `gap_checkout`;
  2. la referencia dice `$('router1_crear')` y `$('Code: derivar')` (SIN el `1`);
  3. las dos conexiones de salida de `router3_confirmar` siguen intactas.

---

## 3. Nodos SIN cambio funcional (NO copiar desde TEST)

Para todos estos, **la logica ya es identica** entre TEST y OPS. Las diferencias que
existen son **ambientales** (conservar OPS) o **cosmeticas** (no tocar). **No** copies
nada de TEST en estos nodos.

### 3.1. AMBIENTAL — conservar el valor de OPS (NO tocar)

| Nodo (OPS) | Diferencia con TEST | Que hacer |
|---|---|---|
| `leer_ambiente`, `PG-0`, `PG-1`, `PG-2`, `PG-3`, `PG-4` | Credencial PostgreSQL: OPS usa `vita_supabase_ops`; TEST usa `vita_supabase_test`. | **Conservar OPS.** No cambiar la credencial. |
| `Webhook` | `path` = `portal-a07-crear-reserva__OPS` (TEST: `__TEST`); `webhookId` propio. | **Conservar OPS.** |
| `Call 'vita_w8cbis_alerta__OPS' (aviso)` | Nombre y `workflowId` apuntan al subworkflow de avisos **de OPS** (TEST apunta al de TEST). | **Conservar OPS.** |
| `Code: derivar` | Dentro del `jsCode`, el **prefijo de idempotencia** es `portal_ops_a07_` (TEST: `portal_test_a07_`). | **Conservar OPS.** **No** pises este `jsCode` con el de TEST: le cambiarias el prefijo de idempotencia. |

> **Importante sobre `Code: derivar`:** es el unico nodo Code, ademas de los dos
> routers, cuyo `jsCode` **difiere** entre TEST y OPS — pero la diferencia es
> **ambiental** (el prefijo `portal_ops_a07_` vs `portal_test_a07_`) y un comentario
> de cabecera `__OPS`/`__TEST`. La **logica es identica**. **No lo copies.**

### 3.2. COSMETICO — no tocar

| Nodo (OPS) | Diferencia con TEST | Que hacer |
|---|---|---|
| `validar_firma_ts_rol` | Comentario de cabecera `__OPS` vs `__TEST`. Logica identica. | Nada. (Ver **nota de seguridad** al final.) |
| `verificar_acceso` | Comentario de cabecera `__OPS` vs `__TEST`. | Nada. |
| `Code: render` | Comentario de cabecera `__OPS` vs `__TEST`. | Nada. |
| `IF aviso 8C-bis (alta nueva)` | UUID interno de la condicion (distinto en cada instancia). `leftValue`/`operator`/`combinator` identicos. | Nada. |
| Todos | Posiciones (x,y) y orden de aparicion en el array de nodos. | Nada. |

### 3.3. IDENTICOS (logica y parametros) — no tocar

`router0_precheck`, `router2_pago`, `router4_recheck`, `Code: render` (logica),
`IF acceso`, `IF0 seguir`, `IF1 seguir`, `IF2 seguir`, `IF3 recheck`, `Respond`.

> Nota sobre `Respond`: los exports vivos omiten `respondWith` (usan el default
> `firstIncomingItem`); el template del repo lo declara explicito. Es el **mismo
> comportamiento**. No hay nada que hacer en OPS.

---

## 4. Verificacion posterior (obligatoria)

1. En n8n, **exporta** el workflow OPS ya modificado (menu del workflow ->
   *Download* / *Export*). Guardalo como, por ejemplo,
   `portal-a07-crear-reserva__OPS.json`.
2. Corre el verificador read-only (no toca nada, solo compara):

```bash
python3 verificador_a07.py \
  portal-a07-crear-reserva__OPS.json \
  portal-a07-crear-reserva__TEMPLATE.json \
  portal-a07-crear-reserva__TEST.json
```

3. **Criterio de exito:** el verificador imprime
   `RESULTADO: PARIDAD FUNCIONAL CONFIRMADA (exit 0)`.
   - Si aparece `[FALLA CONDUCTA]` o `DIFERENCIAS FUNCIONALES`, **algo del `jsCode`
     no quedo bien**: revisa el nodo y JSON path que reporta.
   - La nota `[HMAC]` que imprime el verificador es informativa (describe el dummy
     sintetico del fallback); **no** invalida la paridad ni implica ninguna accion.
4. **Chequeo visual** en n8n (rapido): abri `router1_crear` y `router3_confirmar` y
   confirma los `gap_checkin`/`gap_checkout` y las refs limpias, como se indico en 2.1 y 2.2.
5. Corre `PLAN_PRUEBAS_A07.md`.

---

## 5. Nota sobre el fallback HMAC (aclaracion, sin accion)

En **ambos** exports (TEST y OPS), el nodo `validar_firma_ts_rol` trae, en la linea del
ternario que asigna `SECRET`, un **dummy sintetico de 64 caracteres, sin valor
operativo**. Se utiliza unicamente en los exports de trabajo para preservar longitud;
**no es el secreto real**. Como es **identico** en TEST y OPS, **no** forma parte de
esta alineacion.

Los artefactos versionables (`TEMPLATE` y `CANDIDATO_SANITIZADO`) lo reemplazan por el
placeholder `__PEGAR_SECRETO_O_USAR_VARIABLE__`. No hay nada que corregir ni rotar por
este punto: es solo una aclaracion para que el dummy no se confunda con un secreto.

---

## 6. Apendice — Optimizacion opcional (default: NO aplicar ahora)

Preguntaste si los dos routers pueden **optimizarse** al pasarlos a OPS.

**Recomendacion honesta: llevalos TAL CUAL** (la logica de TEST ya esta validada), y
dejemos la optimizacion como un **micro-refactor OPCIONAL y separado**, aplicado a
**ambos** entornos (TEST y OPS) con su propio test y re-fingerprint. Motivos:

- La unica optimizacion razonable es reemplazar la cadena de `if` de los dos
  gap-errors por un **mapa** `{codigo: mensaje}`. Es **comportamiento identico**, pero
  el ahorro es **marginal** (~4 lineas) y **duplicado** entre los dos nodos (los Code
  nodes de n8n no comparten scope facilmente; centralizar dos mensajes no compensa).
- Mezclar un refactor con esta alineacion **rompe la verificabilidad**: hoy el
  `jsCode` corregido es **byte-identico** al de TEST (con refs limpias), y el
  verificador da paridad exacta. Si ademas optimizamos, ya no compara "igual a TEST"
  sino "igual a una variante nueva", y hay que re-validar TEST primero.
- La disciplina de "un bloque por conversacion" y "correcciones quirurgicas, no
  reescrituras" tambien empuja a **no** bundlear.

Si aun asi lo queres, la variante map-driven seria (misma salida exacta), para
`router1_crear`:

```javascript
// ... dentro de mapErr(e), reemplazando los dos bloques if de gap por:
const GAP = {
  checkin_pisa_checkout_anterior:  'gap_checkin: El check-in queda demasiado cerca del checkout anterior. Elegí un horario de entrada más tarde.',
  checkout_pisa_checkin_posterior: 'gap_checkout: El check-out queda demasiado cerca del check-in posterior. Elegí un horario de salida más temprano.'
};
if (GAP[e]) return { ok:false, error: { code:'conflicto', message: GAP[e], detail:null } };
```

y el analogo en `router3_confirmar` devolviendo el envelope `{recheck:false, envelope:{...}}`.
**Pero el default recomendado es aplicar la version tal-cual de esta guia**, y tratar
el refactor como bloque propio si algun dia se decide.

---

*Fin de la guia. Cualquier `[FALLA]` del verificador viene con nodo y JSON path para localizar el problema.*
