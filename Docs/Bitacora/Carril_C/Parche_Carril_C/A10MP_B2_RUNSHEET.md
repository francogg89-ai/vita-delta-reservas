# A10-MP · Bloque 2 — Gateway patch (`portal-api`) · RUNSHEET

**Alcance:** SOLO el gateway. Agrega el validador `payloadRegistrarCobro` + la entrada de CATALOG `cobranza.registrar_cobro`. **Puramente aditivo.** No toca ninguna acción existente; `cobranza.registrar_saldo` (W10/A10) **queda intacto y convive** (D-C-61). No toca el handler, ni la firma, ni el dispatch.

**Entregable:** `A10MP_B2_portal-api_index.ts` → reemplaza `supabase/functions/portal-api/index.ts` (la Edge Function se despliega como archivo completo).

---

## 1. Qué cambió (exacto)

Dos inserciones, ambas **antes** del `CATALOG` el validador / **dentro** del `CATALOG` la entrada (sin reabrir nada):

1. **Validador `payloadRegistrarCobro`** (+ consts `ENUM_SUBTIPO_TRANSF_GW`, `ORIGEN_OTROS_MAX_GW`, `DESC_OTROS_MAX_GW`, `CONTROL_EN_PAYLOAD_A10MP`), insertado justo antes de `const CATALOG`. Reusa `MONTO_MAX_A10_GW`, `MAXLEN_GW`, `IDEM_RE_GW` (ya existentes). Declarado antes del CATALOG → sin TDZ (L-C-11).
2. **Entrada de CATALOG** `'cobranza.registrar_cobro'`, después de `'cargar.gasto_interno'`:
   ```ts
   'cobranza.registrar_cobro': { handler: 'n8n', roles: ['vicky', 'socio'],
     webhook: 'portal-a10mp-registrar-cobro__TEST',
     validate: payloadRegistrarCobro, injectActor: true, isWrite: true },
   ```
   `idempotency_key` EN PAYLOAD (como A10/W10) → **NO** lleva `needsIdempotencyKey`. `injectActor:true`, `isWrite:true`.

**Métricas:** +105 líneas (incluye comentarios). Entradas n8n en CATALOG: **13 → 14**. `cobranza.registrar_saldo` sigue presente (coexistencia).

---

## 2. Contrato que valida el gateway (D-C-62)

Payload aceptado (espeja W09), reject-unknown:
```
id_reserva (int>0, requerido)
monto_efectivo / monto_transferencia / monto_otros (number ≥0, ≤2 dec, ≤NUMERIC(12,2); ausente/null → 0)
subtipo_transferencia ('bancaria'|'mp'; default 'bancaria')
origen_otros / descripcion_otros (requeridos SOLO si monto_otros>0; prohibidos si ==0)
idempotency_key (8..64 [A-Za-z0-9_-], EN PAYLOAD)
notas (opcional, ≤1000)
```
Reglas: **suma `ef+tr+ot` > 0** (al menos una porción). El tope **`≤ saldo_real` NO se valida acá** — es autoridad del wrapper (anti-sobrepago HARD in-txn, D-C-64). Rechaza claves de control en payload (`actor/rol/nonce/source_event/creado_por/request_ts`). Devuelve el payload **normalizado** (montos default 0, subtipo default, otros `trim|null`).

Errores que produce el gateway (antes de firmar): `payload_invalido` (forma/tipos/enum/decimales/suma 0/otros mal/control), `rol_no_permitido` (jenny). El resto (`conflicto` por sobrepago/mismatch, `no_encontrado`, `estado_incierto`) los produce el wrapper aguas abajo.

---

## 3. Verificación hecha (local)

| Check | Resultado |
|---|---|
| `tsc` strict (+ `noUnusedLocals/Parameters/noImplicitReturns`) sobre el `index.ts` **sin** patch | **EXIT 0** (baseline; el harness es fiel) |
| `tsc` strict sobre el `index.ts` **con** patch | **EXIT 0** |
| Unit test de lógica de `payloadRegistrarCobro` (18 casos) | **18/18 OK** |

Casos del unit test (todos verdes): efectivo solo · transferencia bancaria (default) · transferencia MP · mixto 3 porciones · otros sin origen → reject · otros sin descripción → reject · otros==0 con origen → reject · suma 0 → reject · sin porciones → reject · key corta → reject · clave desconocida → reject · control `actor` en payload → reject · monto 3 decimales → reject · monto negativo → reject · subtipo inválido → reject · id no entero → reject · payload no objeto → reject · notas larga → reject.

### Re-typecheck por tu cuenta
Con `A10MP_B2_typecheck_shims.d.ts` + `A10MP_B2_typecheck_tsconfig.json` en el mismo dir que el `index.ts` (renombrá a `index.ts`):
```
tsc -p tsconfig.json    # esperado: EXIT 0, sin salida
```
*(El harness shimea `Deno` y el import `jsr:@supabase/...` para tipar local; no se despliega.)*

---

## 4. Smokes posibles AHORA a nivel gateway (sin el wrapper todavía)

El wrapper `portal-a10mp-registrar-cobro__TEST` **aún no existe** (es el bloque 3). Igual podés validar el gateway:

- **jenny** (JWT de jenny) → `rol_no_permitido` **en el gateway, antes de firmar** (no toca n8n). ✅ esperado.
- **vicky/socio** con payload inválido (ej. `monto_otros>0` sin `origen_otros`, o `idempotency_key` corta, o todas las porciones en 0) → `payload_invalido` **en el gateway** (no toca n8n). ✅ esperado.
- **vicky/socio** con payload **válido** → el gateway firma y despacha a `portal-a10mp-registrar-cobro__TEST`. Como el webhook no existe aún → dispatch no confiable → **`estado_incierto`** (isWrite). Esto es **esperado hasta el bloque 3**; no escribe nada.

---

## 5. Deploy

- **Seguro de desplegar ya:** el patch es aditivo y no afecta acciones existentes (sus sobres quedan byte-idénticos). Podés desplegarlo ahora o junto con el wrapper.
- La acción `cobranza.registrar_cobro` queda **usable recién cuando exista el wrapper** `portal-a10mp-registrar-cobro__TEST` (bloque 3). Hasta entonces, llamarla da `estado_incierto` (inofensivo).
- `config.toml` sin cambios (`verify_jwt=false` ya está).

---

## 6. Lo que NO está en este bloque

- El **wrapper** n8n `portal-a10mp-registrar-cobro__TEST` (bloque 3: injerto W09 + idempotencia W10 + preámbulo gateway).
- Los **smokes** HMAC directo + JWT gateway de los 11 casos (bloque 4).
- El **runsheet final** + diagnóstico de compatibilidad (bloque 5).

**Próximo paso:** bloque 3 — wrapper. Lo construyo con builder Python clonando un template de wrapper-write validado e injertando (a) la lógica N3 de W09 (recargo + líneas), (b) el nodo transaccional consolidado con advisory lock + idempotencia (patrón W10), todo bajo el preámbulo `Webhook → validar_firma_ts_rol → leer_ambiente → verificar_acceso → derivar → PG_cobro_mp → render → Respond`.
