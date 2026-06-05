# 8C-bis_CIERRE.md — Cierre formal Sub-etapa 8C-bis

**Sub-etapa:** 8C-bis — Alerta por mail de reserva próxima (notificación interna)
**Estado:** ✅ Cerrada (TEST validado con envío real + enganche OPS publicado y activo)
**Fecha de cierre:** 2026-06-04
**Origen formal:** item 3.1 de `Pendiente_pre_produccion.md` (notificación a Jennifer) y D-8C-21 (alerta por reserva próxima, prevista como Bloque 4 opcional posterior a 8C)
**Entorno de validación:** TEST (`vita-delta-test`) — batería de lógica con pin data + envío real de mail confirmado
**Entorno de operación:** OPS (`vita-delta-ops`) — enganche publicado y activo; primera ejecución real quedará registrada con la próxima reserva real (ver §8)
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3` (sin cambios; 8C-bis no toca schema)
**Autores:** Franco (titular) + Claude (arquitecto)
**Decisiones registradas:** D-8Cbis-01 a D-8Cbis-10

---

## 1. Resumen ejecutivo

La sub-etapa 8C-bis construyó la **alerta por mail de reserva próxima**: cuando se
confirma una reserva cuyo check-in cae dentro de la ventana **[hoy, hoy+7]** (zona
horaria America/Argentina/Buenos_Aires), el sistema envía automáticamente un aviso por
correo a los responsables operativos (Franco, Rodrigo) y a la coordinación de limpieza
(Jennifer). El aviso es **mínimo y no sensible**: comunica que hay una reserva próxima
(cabaña, entrada, salida) y enlaza al calendario correspondiente; no incluye montos,
datos del huésped, teléfono ni notas.

El componente es un **sub-workflow independiente** (`vita_w8cbis_alerta__OPS`) invocado
desde el formulario de carga 8B mediante un nodo Execute Workflow, **en rama lateral**:
el formulario 8B sigue su curso y le responde al operador "Reserva confirmada" de forma
totalmente independiente del resultado del aviso. Si el mail falla, la reserva confirmada
**no se ve afectada** — esta es la garantía estructural central de la sub-etapa.

8C-bis es de **solo lectura** sobre las tablas transaccionales: consulta una reserva por
`id_reserva` (un `SELECT` sobre `reservas` + `cabanas`) y no invoca ninguna función del
motor ni escribe en ninguna tabla. No toca schema ni funciones SQL.

El trabajo se desarrolló con la metodología habitual: diseño aprobado por bloques,
validación íntegra en TEST (incluido un envío real de prueba) antes de promover, y
enganche quirúrgico en OPS con verificación read-only del workflow de producción antes y
después de cada cambio.

---

## 2. Qué se construyó

- **Sub-workflow de alerta (TEST):** `vita_w8cbis_alerta__TEST` (id `TdTlv9ZhswwzijF2`,
  13 nodos), validado con envío real, inactivo.
- **Sub-workflow de alerta (OPS):** `vita_w8cbis_alerta__OPS` (id `fHzMFj7pGMKuYEOb`,
  13 nodos), publicado y activo, con destinatarios reales.
- **Enganche en 8B TEST:** `vita_w8b_carga_reserva__TEST` (id `Xk1MNQWXUm7Z5e9W`) —
  rama lateral agregada manualmente y validada end-to-end.
- **Enganche en 8B OPS:** `vita_w8b_carga_reserva__OPS` (id `FEJ5KL24MyscLuvA`,
  el formulario de producción) — rama lateral agregada, publicada y activa.

### 2.1 Topología — sub-workflow 8C-bis

```
Disparo 8C-bis (Execute Workflow Trigger, 5 workflowInputs explícitos:
                id_reserva, id_pre_reserva, entorno, source, operador)
  → Validar entrada (Code: id_reserva entero > 0, entorno ∈ {test, ops})
  → Entrada válida? (IF)
       false → Stop: entrada inválida (noOp)
       true  → Reserva por id (read-only) (Postgres SELECT reservas + cabanas por id)
  → Reserva encontrada? (IF)
       false → Stop: reserva no encontrada (noOp)
       true  → Ventana + armar mail (Code: CFG por entorno, ymd(), ventana [hoy, hoy+7] BA,
                                          arma asunto/cuerpos/destinatarios)
  → En ventana? (IF)
       false → Fuera de ventana, no se envía (noOp)
       true  → Mail operativo (SMTP, Continue On Fail)
            → Mail limpieza (SMTP, Continue On Fail)
            → Consolidar resultado (Code: estado de cada envío, aviso de no-afectación)
```

### 2.2 Enganche en 8B (rama lateral, TEST y OPS)

```
IF P3 OK (true) → PUNTO EXTENSION 8C (noOp)
PUNTO EXTENSION 8C → [ Build Response   (rama principal: item original, responde al operador)
                       Call 8C-bis       (rama lateral: invoca el sub-workflow) ]
Call 8C-bis → (sin salida; hoja lateral)
Build Response → Form Ending
```

- El nodo Call pasa `entorno: "test"` en 8B TEST y `entorno: "ops"` en 8B OPS (valor
  fijo), de modo que cada formulario selecciona el bloque de destinatarios correcto.
- El Call tiene `onError: continueRegularOutput`; los nodos de mail tienen
  `Continue On Fail` + `Always Output Data`.

---

## 3. Decisiones registradas (D-8Cbis-01 a D-8Cbis-10)

| ID | Decisión |
|---|---|
| D-8Cbis-01 | Canal de notificación = **mail** (SMTP), no Telegram ni WhatsApp. WhatsApp queda reservado para comunicación externa con huéspedes (PROD) |
| D-8Cbis-02 | Disparo **en rama lateral** desde el PUNTO EXTENSION de 8B (post-`confirmar_reserva` OK), nunca en serie: el resultado del mail no puede afectar la respuesta al operador ni la reserva |
| D-8Cbis-03 | Sub-workflow **independiente** invocado por Execute Workflow, con `workflowInputs` explícitos (no passthrough): id_reserva, id_pre_reserva, entorno, source, operador |
| D-8Cbis-04 | Fuente de datos = **una query read-only por `id_reserva`** directa a `reservas` + `cabanas`. NO se usan las vistas de calendario (filtran por ventana temporal y no sirven para lookup puntual). `confirmar_reserva()` solo devuelve ids, por eso se consulta aparte |
| D-8Cbis-05 | **Privacidad por construcción:** el mail solo trae cabaña, entrada y salida + enlace al calendario. NO montos, NO huésped, NO teléfono, NO notas. El cuerpo de limpieza enlaza al calendario de limpieza (sin montos); el operativo, al operativo |
| D-8Cbis-06 | Ventana de disparo = **[hoy, hoy+7] inclusive**, TZ America/Argentina/Buenos_Aires; fechas normalizadas a `YYYY-MM-DD` con helper `ymd()` (robusto a timestamps, L-8C-02) |
| D-8Cbis-07 | Manejo de error: mails con `Continue On Fail`; si un mail falla, la reserva confirmada queda confirmada. **Sin deduplicación persistente** y sin tabla nueva (riesgo de doble aviso por reejecución manual aceptado y documentado, §7) |
| D-8Cbis-08 | Configuración por entorno (`CFG.test` / `CFG.ops`) dentro del nodo "Ventana + armar mail": el bloque `test` apunta al mail de Franco (red de seguridad para pruebas manuales); el bloque `ops` a los destinatarios reales |
| D-8Cbis-09 | Remitente SMTP = Gmail personal de Franco (credencial n8n "SMTP gmail") **a título temporal**; migrable al futuro mail propio de las cabañas cambiando solo la credencial/remitente, sin rediseño |
| D-8Cbis-10 | Validación de entrada estricta en el sub-workflow: si `id_reserva` no es entero positivo o `entorno` no es válido, se corta sin enviar (rama "Stop: entrada inválida") |

---

## 4. Hallazgos técnicos

1. **`confirmar_reserva(payload)` solo devuelve `{ ok, id_reserva, id_pre_reserva }`**
   (schema §10.6): no trae cabaña, fechas ni huésped. Por eso 8C-bis consulta los datos
   de la reserva con su propia query por `id_reserva`, en lugar de recibirlos del 8B.
2. **Las vistas `vista_calendario` y `vista_limpieza_semana` filtran por ventana temporal
   en su `WHERE`**: no sirven para un lookup puntual por id. Se usó un `SELECT` directo a
   `reservas` + `cabanas` (sin join a `huespedes`, por privacidad).
3. **Execute Workflow emite el output del sub-workflow, no el item original.** Si el Call
   se conectara en serie hacia `Build Response`, rompería la respuesta al operador. De ahí
   la rama lateral (D-8Cbis-02): el PUNTO EXTENSION alimenta `Build Response` y `Call` en
   paralelo, y el Call queda como hoja sin salida.
4. **Carácter de tabulación heredado en un destinatario:** durante la adaptación a OPS, el
   mail de Rodrigo quedó con un `\t` pegado por copy-paste (`'\trodrigo...'`), que el
   servidor SMTP habría rechazado. Se detectó por inspección del JSON y se corrigió
   (L-8Cbis-02).
5. **Draft vs. versión publicada:** un cambio guardado en n8n no entra en producción hasta
   pulsar "Publish". Se detectó que el mail de Jennifer estaba en el draft pero la
   `activeVersion` aún tenía el mail temporal; se confirmó la publicación antes del cierre
   (L-8Cbis-03).

---

## 5. Contenido del mail (contrato de privacidad)

**Asunto:** `[Vita Delta] Nueva reserva proxima - <cabaña> - <fecha_checkin>`

**Cuerpo (texto plano):**

```
Se confirmo una reserva proxima.

Cabana: <cabaña>
Entrada: <YYYY-MM-DD>
Salida: <YYYY-MM-DD>

Ver calendario <operativo | de limpieza>:
<URL del calendario correspondiente>
```

- **Operativo** → destinatarios operativos + enlace al calendario operativo.
- **Limpieza** → destinatario de limpieza + enlace al calendario de limpieza (sin montos).
- No se incluye ningún dato comercial ni personal: el detalle se consulta abriendo el
  calendario, que ya tiene su propio control de acceso (Basic Auth, D-8C-20).

---

## 6. Validación en TEST — ✅ completa

**Lógica (con pin data, sin escribir en la base):**

| Caso | Resultado |
|---|---|
| Check-in dentro de la ventana [hoy, hoy+7] | ✅ envía |
| Check-in fuera de la ventana | ✅ no envía (rama "Fuera de ventana") |
| Borde inferior (check-in = hoy) | ✅ envía |
| Borde superior (check-in = hoy+7) | ✅ envía |
| `id_reserva` inexistente | ✅ corta en "Reserva no encontrada" |
| Entrada inválida (id/entorno) | ✅ corta en "Entrada inválida" |

**Envío real:** corrida real con reserva de TEST (Bamboo), **dos mails entregados** (250
OK) a la casilla de Franco; `ymd()` corrigió correctamente un timestamp; cuerpos sin datos
sensibles confirmados.

**Aislamiento (la prueba clave) — enganche en 8B TEST:** con pin data se forzó el camino
de éxito hasta P3 → PUNTO EXTENSION → [Build Response + Call], con el **Call pineado para
fallar**. Resultado: `Build Response` emitió **"✅ Reserva confirmada"** con el detalle
correcto (leído del item original de la rama principal, no del Call). Demostrado
end-to-end que **el fallo del aviso no afecta la confirmación**.

**Corrida real desde la URL del formulario 8B TEST:** Franco confirmó que el mail llegó.

---

## 7. Lo que NO se hizo (alcance respetado)

- **Sin deduplicación persistente ni tabla de control** (D-8Cbis-07): una reejecución
  manual de una reserva ya confirmada podría reenviar el aviso. Riesgo aceptado para esta
  sub-etapa; el disparo normal (una confirmación = un aviso) no duplica.
- **Sin disparo por cron/polling:** el aviso se dispara únicamente desde el PUNTO
  EXTENSION de 8B, en el momento de la confirmación.
- **Sin migración del remitente:** sigue usándose el Gmail personal de Franco; la
  migración al futuro mail de las cabañas es trabajo posterior (cambio de credencial, sin
  rediseño — D-8Cbis-09).
- **Sin modificación de schema ni funciones SQL:** 8C-bis es solo lectura + envío.
- **Sin enganche del resguardo (Sheet) ni otros consumidores del PUNTO EXTENSION:** 8C-bis
  es el único consumidor enganchado en este punto por ahora.

---

## 8. Estado en OPS — ✅ publicado y activo

A diferencia de 8C (que cerró sin smoke OPS), 8C-bis cierra **enganchado, publicado y
activo en producción**:

- `vita_w8cbis_alerta__OPS` (`fHzMFj7pGMKuYEOb`): credencial Postgres `vita_supabase_ops`,
  5 `workflowInputs`, bloque `ops` con destinatarios reales (operativo: Franco + Rodrigo;
  limpieza: Jennifer), URLs reales de calendario OPS, mails con Continue On Fail.
  Publicado con el mail de Jennifer activo.
- `vita_w8b_carga_reserva__OPS` (`FEJ5KL24MyscLuvA`, formulario de producción): rama
  lateral verificada contra el JSON en vivo (PUNTO EXTENSION → [Build Response + Call];
  Call sin salida; `entorno: "ops"`; motor P1/P2/P3, compensación, Build Response y Form
  Ending intactos; `source_event` `n8n_ops_...`; path real de OPS). Publicado.

**Decisión operativa de Franco:** no se hizo una carga de prueba real adicional en OPS,
dado que el formulario ya está operando con reservas reales. La **primera ejecución real
de 8C-bis quedará registrada con la próxima reserva real** que se cargue con check-in
dentro de la ventana. La garantía de no-afectación (validada en TEST) protege esa primera
corrida: aun si el envío fallara, la reserva quedaría confirmada igual.

---

## 9. Artefactos entregados

- `vita_w8cbis_alerta__TEST` (id `TdTlv9ZhswwzijF2`) — sub-workflow validado (envío real).
- `vita_w8cbis_alerta__OPS` (id `fHzMFj7pGMKuYEOb`) — sub-workflow de producción, activo.
- `vita_w8b_carga_reserva__TEST` (id `Xk1MNQWXUm7Z5e9W`) — enganche lateral validado.
- `vita_w8b_carga_reserva__OPS` (id `FEJ5KL24MyscLuvA`) — enganche lateral en producción.
- `8C-bis_CIERRE.md` — este documento.

---

## 10. Próximos pasos (post-8C-bis)

1. **Registrar la primera ejecución real** de 8C-bis cuando entre la próxima reserva con
   check-in en ventana, y verificar la entrega a los tres destinatarios reales.
2. **Migración del remitente SMTP** al futuro mail propio de las cabañas (cambio de
   credencial/remitente, sin rediseño — D-8Cbis-09).
3. **Residuos cosméticos no bloqueantes:** el sub-workflow OPS no necesita estar "activo"
   por sí mismo (se invoca por Execute Workflow); puede desactivarse sin efecto. La
   descripción del workflow ya fue alineada a `vita_supabase_ops`.
4. **Resto de `Pendiente_pre_produccion.md`:** ítems no relacionados con la notificación,
   a continuar según prioridad.
5. **Camino a PROD:** webhook MercadoPago, Meta/WhatsApp Business API, frontend público —
   fuera del alcance de esta sub-etapa.

---

*Fin del cierre formal de 8C-bis. Sub-workflow de alerta por mail de reserva próxima
([hoy, hoy+7] TZ BA), validado en TEST con envío real y enganchado en rama lateral al
formulario de carga 8B en TEST y en OPS. Publicado y activo en producción con
destinatarios reales (Franco, Rodrigo, Jennifer). Solo lectura, sin tocar schema ni motor;
el resultado del aviso nunca afecta la reserva confirmada. La primera ejecución real
quedará registrada con la próxima reserva en ventana. No reabre los cierres de 8B, 8C ni
8D.*
