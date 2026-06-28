# PROMOCIÓN CARRIL C A OPS — BLOQUE E (wrappers) + hallazgos de sesión — CIERRE

**Etapa:** Promoción del Carril C a OPS — **Bloque E** (los 13 wrappers n8n) y los hallazgos/fixes surgidos al validarlos en producción. Esta bitácora cierra el Bloque E y deja registrado lo que la misma sesión resolvió en los **Bloques F** (aviso 8C-bis en A07) y **G** (frontend), más un **incidente de datos en OPS** imprevisto.

**Estado:** ✅ **Bloque E cerrado.** Los 13 wrappers `__OPS` están en OPS y funcionando, validados con **escrituras reales** (cobro A10-MP y alta A07). El aviso 8C-bis (Bloque F) disparó en el alta real. El frontend (Bloque G) quedó desplegado en Vercel (commit `3a7b82d`) con los fixes de esta sesión.

**Ámbito:** Documental + de validación. Claude diseñó/validó/generó artefactos; **Franco ejecutó todos los writes** (n8n, Supabase, Vercel, commits). Claude no tocó OPS ni n8n directamente.

**Sobre los satélites — NO se tocan en esta bitácora.** Según el `PROMOCION_CARRIL_C_OPS_PLAN.md` (§6) y el precedente del Carril B (`PROMOCION_CARRIL_B_OPS_CIERRE.md`), la propagación a los documentos satélite + la formalización de decisiones **D-PROMO-C-XX** y lecciones **L-PROMO-C-XX** se hacen en **un único bloque de cierre al final de la promoción** (tras los Bloques H e I), no bloque por bloque. Las decisiones y lecciones de esta sesión quedan aquí como **provisionales**, listas para consolidarse en ese cierre final.

---

## 1. Mapa de la promoción

| Bloque | Qué es | Estado |
|---|---|---|
| A | Snapshot baseline read-only de OPS | ✅ hecho |
| B | Infra del portal por DDL (sin seed) | ✅ hecho |
| C | Usuarios Auth OPS + seed `portal_usuarios` | ✅ hecho |
| D | Gateway `portal-api` a OPS | ✅ hecho |
| **E** | **Los 13 wrappers n8n a OPS** | **✅ cerrado (esta bitácora)** |
| F | Aviso 8C-bis en el A07 de OPS | ✅ validado (alta real #11 disparó el aviso, `entorno=ops`) |
| G | Frontend OPS (build + deploy Vercel) | ✅ desplegado (commit `3a7b82d`) + banner P-FE-09 resuelto |
| H | Smokes read-only end-to-end + fingerprint estructural | ⏳ pendiente |
| I | Bump canónico v1.9.0 | ⏳ pendiente |
| Cierre | Bloque de cierre + propagación a satélites (D-PROMO-C-XX) | ⏳ pendiente (al final) |

---

## 2. Bloque E — los 13 wrappers `__OPS`

Catálogo del gateway (14 entradas) = 1 Edge (`sesion.contexto`, handler propio) + **13 wrappers n8n**: 8 lecturas (A03 `calendario.limpieza`, A04 `calendario.operativo`, A05 `reserva.detalle`, A06 `prereservas.activas`, A12 `cobranza.saldos`, A24 `historico.reservas`, A25 `ingresos.cobrados_periodo`, A13 `gastos.listado`) + 5 escrituras (A07 `reserva.crear_manual`, A08 `bloqueo.crear_manual`, W10 `cobranza.registrar_saldo` deprecated-in-place, A11 `cargar.gasto_interno`, A10-MP `cobranza.registrar_cobro`).

Cómo se armaron en OPS (todos con webhook path sufijo `__OPS`, credencial `vita_supabase_ops` en los nodos PG, HMAC de OPS en `validar_firma_ts_rol`):

- **E1 (8 lecturas):** duplicación manual por Franco, guiada por checklist. Riesgos marcados y cubiertos: path `__OPS` (evita colisión con TEST en la misma instancia n8n), reasignación de credencial en **todos** los nodos PG (A03=6, A04=5), reemplazo del HMAC heredado de TEST.
- **E2 (A08, A11, W10):** armadas manualmente.
- **E3 (A07, A10-MP):** JSON generados con **builder Python + verificador estructural** (nunca a mano), `node --check` sobre los jsCode.

**Validación con escrituras reales (no smokes sintéticos):** cobro de saldo vía **A10-MP** (reserva #8) y **alta** vía A07 (reserva #11) salieron correctas end-to-end.

---

## 3. Hallazgo crítico — candado anti-OPS `TEST-only` embebido en el código

Al probar el cobro, A10-MP devolvía `ambiente_incorrecto / wrapper TEST-only` pese a que `leer_ambiente` leía `ops` bien. Causa: un **candado hardcodeado** en el `jsCode` del nodo `verificar_acceso`:

```js
if (dbAmbiente !== 'test') {
  return [{ json: { acceso:false, error:'ambiente_incorrecto', message:'wrapper TEST-only' } }];
}
```

Discrimina el ambiente **por un valor literal** (`!== 'test'`) — anti-patrón frente al principio del proyecto (discriminar por credencial/seed/firma). El chequeo legítimo (`dbAmbiente !== v.ambiente_esperado`) **ya estaba** y se conserva.

**Por qué pasó (reconocido):** el builder de promoción transformó lo "externo" del wrapper (paths, credenciales, HMAC, el Call del aviso) pero **no auditó la lógica interna de los nodos**, donde vivía el candado.

**Barrido sobre los 13 wrappers:** el candado estaba **solo en A10-MP y W10** (los dos de cobranza); los otros 11, limpios.

**Resolución:**
- **A10-MP:** candado removido (Franco editó el nodo `verificar_acceso` directamente en n8n, sin perder credencial/HMAC). Cobro #8 → OK.
- **W10:** **se conserva el candado a propósito.** W10 está deprecated-in-place y el frontend **nunca lo invoca** (usa A10-MP); el candado jamás se dispara y funciona como protección coherente con su estado deprecated. **No es deuda.**
- **A07:** auditoría interna exhaustiva (todos los `jsCode` + SQL) → **sin candado**; su `verificar_acceso` usa solo el chequeo correcto. Único hallazgo: prefijo cosmético del `idempotency_key` (`portal_test_a07_` → corregido a `portal_ops_a07_`; sin efecto funcional, las bases TEST/OPS son separadas).

---

## 4. Bloque F — aviso 8C-bis en el alta por portal (A07)

El A07 de OPS dispara el aviso 8C-bis por **rama lateral no bloqueante** (Call a `vita_w8cbis_alerta__OPS`, id `fHzMFj7pGMKuYEOb`), con `entorno` autoresuelto desde `leer_ambiente.valor` (no hardcodeado). Validado en el alta real #11: la reserva se creó y el aviso disparó con `entorno=ops`. El sub-workflow es solo-lectura (manda mail; no escribe DB).

---

## 5. Incidente de datos en OPS — corrupción de huéspedes (resuelto)

**Síntoma:** en "Saldos a cobrar", las reservas #5–#10 mostraban todas el mismo huésped ("Marcelo Gómez").

**Causa raíz (confirmada con queries read-only, no asumida):** el `<input type="email">` del huésped en *Crear reserva* (sin `autocomplete`) era **autocompletado por Chrome con el email del operador logueado** (Vicky, `victoriakrankemann@gmail.com`). `upsert_huesped` **deduplica por email** (constraint U4 `uq_huespedes_email`) con `modo='update'` → cada alta nueva **sobrescribía el huésped id 6**, colapsando todas las reservas a ese id (mostraba siempre al último cargado). El frontend tomaba el email **del formulario** (correcto); el bug era el **autofill del navegador**, no el código.

> Una hipótesis inicial (que A12 leía TEST por credencial) fue **descartada con una query**: A12 lee OPS bien. Confirmar con datos en vez de asumir evitó un fix equivocado.

**Corrección de datos** (`CORRECCION_huespedes_OPS.sql`, ejecutado verde, con salvaguarda de ambiente + verificación con rollback): #5–#10 reasignadas a sus huéspedes reales; email de Vicky quitado del id 6; reserva de prueba #4 ($2) eliminada. #1 (no corrupta) intacta.

**Fix de frontend (doble capa, desplegado):**
1. `autoComplete="off"` en el input de email (primera línea de defensa).
2. Validación anti-autofill: rechaza el submit si el email del huésped == email del operador logueado (garantía).

---

## 6. Bloque G — frontend OPS

Desplegado en Vercel (commit `3a7b82d`). Dos fixes de esta sesión, ambos con `typecheck` + `build` EXIT 0 y LF estricto:

- **`CrearReserva.tsx`** — el fix anti-autofill del §5.
- **P-FE-09 (banner) — RESUELTO.** `lib/ambiente.ts` ahora reconoce el ref de OPS (`lpiatqztudxiwdlcoasv`) como ambiente `'ops'`, que **no muestra banner**; `BannerAmbiente.tsx` retorna `null` en OPS. `App.tsx` ya omitía el `pt-8` cuando no hay banner, así que no queda hueco. TEST sigue con su banner amarillo; cualquier ref desconocido, con el rojo defensivo.

---

## 7. Decisiones provisionales (a formalizar como D-PROMO-C-XX en el cierre final)

- **Webhooks `__OPS`.** Los 13 wrappers usan path con sufijo `__OPS`. La instancia n8n aloja TEST y OPS; el sufijo evita colisión de paths. **Paridad TEST↔OPS es lógica** (keys/roles/validators/flags/HMAC/credencial), no byte.
- **CORS del gateway por env var.** `CORS_ALLOW_ORIGIN` obligatoria; el preflight falla si falta; **nunca `'*'`**. En OPS = `https://complejo-vita-delta.vercel.app`.
- **Discriminación de ambiente por `ambiente_esperado`, no por valor literal.** El candado `!== 'test'` se removió de A10-MP; el chequeo válido es `dbAmbiente !== v.ambiente_esperado`. **W10 conserva el candado a propósito** (deprecated, nunca invocado).
- **Idempotency prefix por ambiente.** A07 OPS usa `portal_ops_a07_` (cosmético; bases separadas).
- **Frontend reconoce OPS por ref → sin banner** (resuelve P-FE-09).

## 8. Lecciones provisionales (a formalizar como L-PROMO-C-XX)

- **Al promover wrappers n8n de TEST a OPS, auditar la lógica interna de los nodos** (`jsCode` y SQL) por guards de ambiente hardcodeados (`!== 'test'`, mensajes "TEST-only"), no solo routing/credenciales/HMAC/Call. El candado vivía dentro de `verificar_acceso` y el builder no lo veía. Barrido posterior: solo A10-MP y W10 lo tenían.
- **Autofill del navegador + dedup por email = corrupción silenciosa de datos.** Un `<input type="email">` sin `autoComplete="off"` puede ser llenado por el navegador con el email del operador; combinado con `upsert_huesped` que deduplica por email (U4) en modo update, sobrescribe el huésped y colapsa reservas. Defensa de doble capa: `autoComplete="off"` + validación anti-autofill (email huésped ≠ email operador). Diagnóstico: **confirmar con query, no asumir** (la hipótesis de credencial cruzada se descartó así).

---

## 9. Pendientes y handoff

- **Teardown de la reserva de prueba #11** — `TEARDOWN_reserva_11_OPS.sql` (gate ops; borra pagos/reserva/pre-reserva y el huésped solo si quedó huérfano). Franco lo corre cuando quiera. *(Único ítem operativo abierto de esta sesión.)*
- **Bloque H** — smokes read-only end-to-end por rol (login real jenny/vicky/socio → `sesion.contexto` → una lectura por acción → allowlist: jenny rebota en económicos) + **fingerprint estructural TEST↔OPS** de la infra del portal + alta controlada con verificación del aviso.
- **Bloque I** — bump canónico `6B_SCHEMA_SQL.md` → **v1.9.0** (las 3 estructuras del portal; estructura, **nunca** seeds/secretos/URLs).
- **Cierre final + satélites** — formalizar **D-PROMO-C-XX** / **L-PROMO-C-XX**; propagar a los 6 satélites (ESTADO_ACTUAL CRLF; resto LF); **saldar la deuda D-C-64…70** (A10-MP) **y D-C-71…73** (aviso A07) en el ledger.
- **W10 candado** — dejado a propósito; **no** es deuda.

---

## 10. Artefactos de la sesión

**Wrappers OPS (JSON):** `portal-a10mp-registrar-cobro__OPS.json` (candado removido), `portal-a07-crear-reserva__OPS.json` (sin candado, prefijo `portal_ops_a07_`, Call al aviso). Soporte E3: `E3_smoke_seguridad_escritura__OPS.ps1`, `E3_gate_no_escribe.sql`, `E3_A07_teardown.sql`, `E1_smoke_directo_lectura__OPS.ps1`, `E1_LECTURAS_CHECKLIST.md`.

**Incidente de datos:** `DIAG_A12_huespedes_OPS.sql`, `DIAG_huespedes_universo_OPS.sql`, `DIAG_estado_reservas_corregir_OPS.sql`, `CORRECCION_huespedes_OPS.sql`.

**Frontend:** `CrearReserva.tsx` (+ runsheet), `ambiente.ts`, `BannerAmbiente.tsx`, `FIX_BANNER_OPS_RUNSHEET.md`.

**Limpieza:** `TEARDOWN_reserva_11_OPS.sql`.

**Fuentes:** gateway `Docs/Bitacora/Carril_C/Parche_Carril_C/A10MP_B2_portal-api_index.ts`; templates `Workflows/n8n/Supabase/portal-a*__TEMPLATE.json` (+ `vita_w10_registrar_saldo__TEMPLATE.json`); canónico `Docs/Implementacion/6B_SCHEMA_SQL.md` v1.8.1; plan `Docs/Implementacion/Carril_C/PROMOCION_OPS/PROMOCION_CARRIL_C_OPS_PLAN.md`.
