# BLUEPRINT — Mini-etapa backend A10-MP

**Objetivo:** exponer la cobranza multi-porción + recargo 5% de **W09** a través del gateway `portal-api`, como acción nueva, sin tocar tablas/enums/`registrar_pago`/contabilidad/OPS. Después, B5 frontend sobre este contrato.

**Naturaleza del trabajo:** injerto. La lógica difícil (validación multi-porción, recargo, líneas `saldo`+`extra`, atomicidad) ya está **verificada en W09** (9B_CIERRE, smokes $8.500/$5.000/$1.650 + rollback). El patrón de idempotencia ya está **verificado en W10** (`source_event` determinista + dedup + mismatch→conflicto + recálculo de saldo byte-alineado a A12). A10-MP = **W09 (cuerpo) + W10 (idempotencia/atomicidad-en-una-transacción) + preámbulo estándar del gateway**.

**Decisiones que se lockean en esta etapa (propuestas):** D-C-61..D-C-66 (abajo, §10). Nada se reabre una vez aprobado.

---

## 1. Acción nueva (gateway)

| Campo | Valor |
|---|---|
| **action key** | `cobranza.registrar_cobro` |
| **handler** | `n8n` |
| **roles** | `['vicky', 'socio']` — **jenny excluida** (rebota `rol_no_permitido` EN EL GATEWAY, antes de firmar) |
| **webhook** | `portal-a10mp-registrar-cobro__TEST` |
| **validate** | `payloadRegistrarCobro` (nuevo, §3) |
| **injectActor** | `true` (el actor/persona se inyecta server-side desde el JWT; el wrapper lo usa como `validado_por` en `registrar_pago`) |
| **isWrite** | `true` (dispatch no-confiable → `estado_incierto`, no `error_entorno`, porque la escritura pudo aplicarse) |
| **needsIdempotencyKey** | según transporte elegido (§4) |

Entrada de CATALOG (forma, sin código final):
```ts
'cobranza.registrar_cobro': { handler: 'n8n', roles: ['vicky','socio'],
  webhook: 'portal-a10mp-registrar-cobro__TEST',
  validate: payloadRegistrarCobro, injectActor: true, isWrite: true },
```

---

## 2. Cadena de nodos del wrapper nuevo (injerto)

```
Webhook                         (reemplaza el Form Trigger de W09)
  → validar_firma_ts_rol        (preámbulo gateway: HMAC-SHA256 sobre bytes literales;
                                 whitelist de payload; lee idempotency_key/rol/actor/request_ts;
                                 reject-unknown; ventana anti-replay del HMAC)
  → leer_ambiente               (marcador configuracion_general('ambiente'))
  → verificar_acceso            (rol ∈ {vicky,socio}; coherencia rol↔actor; ambiente)
  → IF acceso                   (false → render acceso/rol → Respond)
  → derivar                     (source_event determinista PII-free desde id_reserva+key — patrón W10;
                                 normaliza porciones; calcula recargo y arma lineas[] — lógica N3 de W09)
  → PG_cobro_mp  [TRANSACCIONAL] (un solo nodo, una transacción — combina W09 N5/N6 + W10 PG_cobranza/verif:
                                  1) pg_advisory_xact_lock(hash(id_reserva||key)) — serializa replays concurrentes
                                  2) idempotencia PRIMERO: ¿existe pago con este source_event?
                                       match  → idempotent_match:true (resumen reconstruido, sin escribir)
                                       difiere→ conflicto 'idempotency_key reutilizada con datos distintos'
                                  3) recalcula saldo_real (byte-alineado a A12: monto_total − SUM(seña+saldo conf))
                                  4) anti-sobrepago HARD: suma_saldo > saldo_real → conflicto, NO escribe nada
                                  5) por cada línea: abortar_si_falla(registrar_pago(linea)) — rollback-all si una falla
                                  6) verificación post: recalcula saldo_real_post; asserts de integridad)
  → render                      (envelope ok/error; mapea mismatch/overpay → conflicto)
  → Respond
```

**Nodos de W09 que se descartan:** `N4 Resumen + Confirmar` y `N7 Éxito` (eran formularios de confirmación humana; los reemplaza el request/response del API).

**Por qué un solo nodo transaccional (refinamiento sobre W09):** W09 usa `N4.5 expandir` + `N5 per-item` con `queryBatching:transaction`. Eso da atomicidad **dentro de una sola ejecución de nodo**, pero la idempotencia (que W09 no tenía) requiere que el **check + el insert estén en la MISMA transacción** para ser race-safe en un endpoint expuesto a red con reintentos. Por eso se consolida la invocación de `registrar_pago` por línea en un único nodo transaccional con advisory lock + idempotency-check-first (patrón probado de W10). **Se preserva exactamente:** `registrar_pago` por línea, `abortar_si_falla`, rollback atómico, recargo, separación del `extra`. **Lo único que cambia** respecto de W09 es que el bucle de `registrar_pago` vive en una transacción única junto al check de idempotencia (en vez de un nodo per-item separado). `registrar_pago`, tablas y enums quedan **intactos**.

---

## 3. Contrato exacto — payload (espeja W09)

```jsonc
{
  "id_reserva":            <int>,        // requerido
  "monto_efectivo":        <number>,     // opcional, default 0 (ARS, ≥0)
  "monto_transferencia":   <number>,     // opcional, default 0 (ARS, ≥0)
  "subtipo_transferencia": "bancaria" | "mp",  // opcional, default "bancaria"; solo relevante si monto_transferencia>0
  "monto_otros":           <number>,     // opcional, default 0 (equivalente ARS, ≥0)
  "origen_otros":          <string>,     // requerido SOLO si monto_otros>0 (1..120)
  "descripcion_otros":     <string>,     // requerido SOLO si monto_otros>0 (1..200)
  "idempotency_key":       <string>,     // requerido, 8..64, /^[A-Za-z0-9_-]+$/
  "notas":                 <string>      // opcional (1..MAXLEN)
}
```

**Validación en el gateway (ANTES de firmar) — `payloadRegistrarCobro`:**
- reject-unknown (cualquier clave fuera de la lista → `payload_invalido`).
- `id_reserva` entero positivo.
- montos: número, `≥ 0`, dentro de `NUMERIC(12,2)`; vacío/ausente → `0`.
- `suma_saldo = ef + tr + ot` debe ser `> 0` → si los tres son 0, `payload_invalido` ("al menos una porción > 0"). *(El tope `≤ saldo_real` NO se valida en el gateway: es autoridad del wrapper, que conoce el saldo vivo — §8.)*
- `subtipo_transferencia` ∈ `{bancaria, mp}`; default `bancaria`.
- `monto_otros > 0` ⇒ exige `origen_otros` y `descripcion_otros` no vacíos; si `monto_otros == 0` y vienen → `payload_invalido` ("origen/descripción de otros sin monto").
- `idempotency_key` con el regex/longitud (igual que A10/W10).
- `notas` opcional, trim, longitud.
- **Control en payload (rechazo explícito, D-C-39):** `actor`, `rol`, `nonce`, `source_event`, `creado_por`, `request_ts` en payload → `payload_invalido` (los inyecta el gateway/JWT, nunca el frontend).
- Devuelve el payload **normalizado/whitelisteado** (lo que se firma y viaja al wrapper). El wrapper revalida idempotentemente (2ª defensa).

**Razón de espejar W09 (no array de porciones):** minimiza riesgo de injerto — el cuerpo de W09 ya espera `monto_efectivo / monto_transferencia / subtipo_transferencia / monto_otros / origen / descripcion`. Un array `porciones[]` obligaría a reescribir N3. Espejo plano = menos superficie de error. (Tu instrucción explícita: espejar salvo razón fuerte; no la hay.)

---

## 4. Idempotencia

- **`idempotency_key`**: requerida, `8..64`, `/^[A-Za-z0-9_-]+$/` (idéntico a A10/W10 y al lifecycle D-FE-20 del frontend).
- **Transporte propuesto: EN PAYLOAD** (como A10/W10). El frontend B5 usará `useEnviar('cobranza.registrar_cobro', 'payload')`. *(Alternativa: SIBLING como A11. Recomiendo payload por linaje directo con A10.)*
- **`source_event` determinista, PII-free** (patrón W10):
  ```
  canon  = String(id_reserva) + '|' + idempotency_key
  hash   = sha256(canon).slice(0,12)
  source_event = 'portal_test_a10mp_res' + id_reserva + '_' + hash
  ```
  **Todas las líneas del evento comparten el mismo `source_event`** (W09 ya agrupa por ese campo; `registrar_pago` lo persiste tal cual — L-9B-01).
- **Dedup dentro de la transacción serializada** (advisory lock sobre `hash(id||key)`):
  - existe `source_event` **y la firma de porciones coincide** → `idempotent_match: true`, devuelve el resumen reconstruido desde los pagos existentes, **sin escribir**.
  - existe `source_event` **y la firma difiere** → `conflicto` ("idempotency_key reutilizada con datos distintos"). *(Mismatch = misma key, distintas porciones — patrón W10 generalizado al evento multi-línea: se compara el multiset de líneas (tipo, medio_pago, monto) existente vs el calculado.)*
  - no existe → valida y registra atómicamente.
- **Retry seguro:** un reintento con la **misma** key tras `estado_incierto` es idempotente — si el evento ya se aplicó, devuelve `idempotent_match`; si no, lo registra fresco. Nunca duplica.

---

## 5. Response exacta

**Éxito (`ok:true`), envelope del gateway:**
```jsonc
{
  "ok": true,
  "data": {
    "source_event":      "portal_test_a10mp_res<ID>_<hash>",
    "cant_lineas":       <int>,      // líneas registradas (saldo + extra)
    "suma_saldo":        <number>,   // aplicado a saldo (efectivo + transferencia + otros)
    "suma_extra":        <number>,   // recargo 5% (tipo='extra'), SEPARADO
    "total_cobrado":     <number>,   // suma_saldo + suma_extra (lo que se le cobra al huésped)
    "saldo_anterior":    <number>,   // saldo_real antes del cobro
    "saldo_real_actual": <number>,   // saldo_real recalculado post-commit (== saldo_anterior − suma_saldo)
    "saldada":           <bool>,     // saldo_real_actual === 0
    "idempotent_match":  <bool>,     // true si fue replay
    "detalle": {                     // desglose para la UI (B5)
      "efectivo":              <number>,
      "transferencia":         <number>,
      "subtipo_transferencia": "bancaria" | "mp" | null,
      "otros":                 <number>,
      "recargo":               <number>   // == suma_extra
    }
  }
}
```
Mapea 1:1 a la UI de B5: *aplicado a saldo* = `suma_saldo`; *extra 5%* = `suma_extra`; *total a cobrar* = `total_cobrado`; *saldo restante* = `saldo_real_actual`.

**Error (`ok:false`):** `{ "ok": false, "error": { "code": <code>, "message": <fijo por código>, "detail"?: {...} } }`

---

## 6. Errores

| code | Cuándo | Escribe algo |
|---|---|---|
| `payload_invalido` | forma/tipos/enum mal, idempotency_key inválida, `suma_saldo==0`, monto negativo, otros sin origen/descripción (o viceversa), claves de control en payload | No |
| `rol_no_permitido` | jenny (rebota EN EL GATEWAY antes de firmar) | No |
| `no_encontrado` | `id_reserva` inexistente / sin reserva confirmada-activa asociada | No |
| `conflicto` | (a) **anti-sobrepago**: `suma_saldo > saldo_real`; (b) **idempotency_mismatch**: misma key, distintas porciones | **No** (a y b rebotan sin tocar la base) |
| `estado_incierto` | `isWrite` + dispatch no-confiable (timeout >10s, HTTP no-2xx, no-JSON, envelope inválido) | **Quizás** (la escritura pudo aplicarse). Reintento con la misma key es seguro |

Mensajes fijos por código (MENSAJE_FIJO_POR_CODIGO del gateway, sin filtrar internals).

---

## 7. Separación contable — cómo se preserva (automática)

- El endpoint escribe **exactamente las mismas filas que W09**: líneas `tipo='saldo'` (efectivo / transferencia / otros) + **una** línea `tipo='extra'` (recargo, marcada `recargo_5_saldo_transferencia`).
- **`registrar_pago`, `pagos`, enums y funciones de distribución quedan INTACTOS.** La separación ya está construida aguas abajo:
  - Distribución: `p1 = SUM(monto_recibido) FILTER (tipo IN ('sena','saldo'))` = **base del 25%**; `p6 = SUM(... ) FILTER (tipo='extra')` = **extra, separado**. El extra **nunca** entra al 25%.
  - **A12** `saldo_real`: `FILTER (tipo IN ('sena','saldo'))` → **excluye extra** → el recargo **no reduce** saldo. ✅
  - **A25** `ingresos`: `tipo IN ('sena','saldo','extra','ajuste','reembolso')` → **incluye extra** → el recargo aparece como caja percibida. **Coherente con tu regla #4** (el extra es plata cobrada, afuera de la base del 25%). **Ver §9 — requiere tu confirmación, no lo cambio.**
- **Conclusión:** A10-MP no agrega ni una línea de lógica contable. Solo produce las filas `saldo`/`extra` que el resto del sistema ya sabe separar.

---

## 8. Anti-sobrepago (HARD, autoridad del wrapper)

- `suma_saldo` (efectivo + transferencia + otros) **no puede superar `saldo_real`** (recalculado in-txn byte-alineado a A12). Si lo supera → `conflicto`, **no escribe nada**.
- El **extra (5%) NO cuenta** para cancelar saldo: `saldo_real_actual = saldo_anterior − suma_saldo` (el extra queda afuera). Verificado en N6/N6b de W09 (assert `saldo_real_post == saldo_anterior − suma_saldo`, que **prueba** que el extra no contaminó el saldo).
- El frontend B5 replicará el bloqueo (D-FE-21), **nunca más estricto** que el gateway (D-FE-23); pero la autoridad final es el wrapper.

---

## 9. Diagnóstico de compatibilidad A12 / A25 / A13

| Endpoint | Filtro de `tipo` | Efecto del nuevo `extra` | Veredicto |
|---|---|---|---|
| **A12** `cobranza.saldos` | `IN ('sena','saldo')` | excluye el extra → **no reduce saldo** | ✅ Sin cambios |
| **A25** `ingresos.cobrados_periodo` | `IN ('sena','saldo','extra','ajuste','reembolso')` | **incluye** el extra → el recargo 5% aparece como caja percibida | ⚠️ **Decisión tuya (§ Decisiones abiertas #3)** — no lo toco |
| **A13** `gastos.listado` | opera sobre `gastos_internos`, no `pagos` | ninguno | ✅ No aplica |

**Sobre A25:** hoy A25 ya suma `extra`. Si en TEST ya se usó W09, los `extra` existentes **ya están** en A25. El nuevo endpoint solo agrega más filas `extra` por la misma vía. Hay dos lecturas válidas:
- **(i) A25 = caja total percibida** (incluye recargo): comportamiento actual, coherente con "el extra es plata que entró". El 25% se calcula aparte sobre base. → **no cambiar nada**.
- **(ii) A25 = solo ingreso base** (seña+saldo): habría que sacar `extra` del filtro de A25 (cambio acotado en el wrapper A25). El recargo se vería en otra vista.

Recomiendo **(i)** (no tocar A25): es lo que ya hace, y tu regla #4 dice que el extra **se suma** (solo que afuera de la base del 25%). Pero es tu llamada.

---

## 10. Deprecación: ¿convive o se deprecia W10?

- **`cobranza.registrar_cobro` (nuevo) CONVIVE con `cobranza.registrar_saldo` (W10).**
- W10 queda **deprecado-in-place**: sigue en el CATALOG y desplegado (funciona), pero **el portal deja de llamarlo** — B5 usa **solo** el endpoint nuevo. No se remueve en esta etapa (no se toca un endpoint que anda; la remoción puede ser un cleanup posterior).
- Se documenta la deprecación en `DECISIONES_NO_REABRIR.md` / `Pendiente_pre_produccion.md` al cierre, con remoción de W10 agendada para después de validar B5 (si querés).

---

## 11. Smokes obligatorios (PS5.1, ASCII-pure CRLF)

Dos caminos por caso: **HMAC directo** (al webhook, firma manual) y **JWT gateway** (vía `portal-api`).

| # | Caso | Esperado |
|---|---|---|
| 1 | efectivo solo ($X) | 1 línea `saldo`; recargo $0; saldo baja $X |
| 2 | transferencia **bancaria** ($X) | `saldo` $X + `extra` round($X·0.05); saldo baja $X (no el extra) |
| 3 | transferencia **MP** ($X) | igual #2 con `medio_pago='transferencia_mp'` |
| 4 | efectivo + transferencia | 2 `saldo` + 1 `extra` (5% solo sobre la transferencia) |
| 5 | efectivo + transferencia + otros | 3 `saldo` + 1 `extra`; otros como efectivo-equiv ARS con traza; recargo solo sobre transferencia |
| 6 | otros solo | `saldo` (efectivo-equiv); recargo $0 |
| 7 | **suma_saldo > saldo_real** | `conflicto`; **0 pagos** con ese source_event (no escribe nada) |
| 8 | **rollback**: una línea forzada a fallar | P0001 → rollback total; **0 pagos** con ese source_event |
| 9 | **jenny** | `rol_no_permitido` EN EL GATEWAY (antes de firmar) |
| 10 | **idempotencia/retry**: misma key 2 veces (mismas porciones) | 2ª → `idempotent_match:true`; **no** duplica |
| 11 | **mismatch**: misma key, distintas porciones | `conflicto` ("idempotency_key reutilizada con datos distintos"); no escribe |

**Cómo se prueba el rollback (#8):** variante de laboratorio que inyecta una línea inválida en el evento (que haga rebotar `registrar_pago` → no-confirmado → `abortar_si_falla` lanza P0001). El bucle corre en una sola transacción → revierte TODO. Assert: `SELECT count(*) FROM pagos WHERE source_event = '<X>'` = **0**. (Replica el test 10 de 9B, ahora por el gateway.)

---

## 12. Entregables (en orden, bloque por bloque)

1. **Este blueprint** (aprobación previa).
2. **Gateway patch**: `payloadRegistrarCobro` + entrada de CATALOG `cobranza.registrar_cobro` (+ const/enum necesarias). Validado con `tsc` strict.
3. **Wrapper nuevo** `portal-a10mp-registrar-cobro__TEST`: builder Python que clona un template de wrapper-write validado y trasplanta (a) N3 de W09 (recargo+lineas), (b) el nodo transaccional consolidado con idempotencia de W10. Verificador estructural de invariantes.
4. **Smokes** (los 11 casos, doble camino).
5. **Runsheet** con matriz por rol (vicky/socio OK; jenny bloqueada).
6. **Diagnóstico de compatibilidad** A12/A25/A13 (este §9, como doc de cierre).

Cada artefacto: entrega individual, sin mega-diffs. SQL de los nodos validado con pglast antes de entregar.

---

## 13. Decisiones a confirmar ANTES de codear

1. **Nombre**: action `cobranza.registrar_cobro`, webhook `portal-a10mp-registrar-cobro__TEST`. ¿OK?
2. **Transporte de `idempotency_key`**: EN PAYLOAD (como W10) → frontend `useEnviar(...,'payload')`. ¿OK? (alternativa SIBLING como A11).
3. **A25**: dejar A25 como está (**incluye** el extra → el recargo cuenta como caja percibida, afuera de la base del 25%). ¿Confirmás (i), o querés (ii) base-only? **No toco A25 sin tu OK.**
4. **Estructura**: consolidar el `registrar_pago` por línea en **un nodo transaccional único** (preserva per-línea + `abortar_si_falla` + rollback atómico; agrega advisory lock + idempotencia en la misma transacción, por ser endpoint de red con reintentos). ¿OK? (alternativa: per-item de W09 + pre-check separado, con ventana de carrera en misma-key concurrente — no recomendado para un endpoint que mueve plata).
5. **"Otros"**: espeja W09 — se registra como `saldo` **efectivo-equivalente ARS** con traza (`medio_original=otros; origen_otros=...; descripcion_otros=...; registrado_como=efectivo_ars`); exige `origen_otros`+`descripcion_otros` si `monto_otros>0`; **no** genera recargo. ¿OK?

**Decisiones que quedarían lockeadas (propuestas):**
- **D-C-61** — Acción `cobranza.registrar_cobro` (multi-porción) expone W09 por el gateway; W10 deprecado-in-place, convive.
- **D-C-62** — Payload espeja W09 (plano, no array); `suma_saldo>0` validado en gateway, `≤saldo_real` autoridad del wrapper.
- **D-C-63** — `idempotency_key` en payload; `source_event` determinista PII-free (`id_reserva`+key); dedup por `source_event`; mismatch→`conflicto`.
- **D-C-64** — `registrar_pago` por línea + `abortar_si_falla` + idempotency-check en **una** transacción con advisory lock (race-safe). `registrar_pago`/tablas/enums intactos.
- **D-C-65** — Separación contable se preserva automáticamente (filas `saldo`/`extra`; A12 excluye extra, A25 lo incluye, 25% sobre base `seña+saldo`).
- **D-C-66** — A25 se mantiene incluyendo `extra` (caja total percibida) — *sujeto a tu confirmación #3*.

---

**Resumen:** A10-MP es un injerto de bajo riesgo: dos cuerpos ya verificados (W09 lógica + W10 idempotencia) sobre el preámbulo estándar del gateway, sin tocar el motor ni la contabilidad. Confirmá los 5 puntos del §13 y arranco con el bloque 2 (gateway patch).
