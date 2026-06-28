# PROMOCIÓN CARRIL C A OPS — BLOQUE H (smokes read-only + fingerprint estructural) — CIERRE

**Etapa:** Promoción del Carril C (Portal Operativo Interno) a OPS — **Bloque H**: verificación de **paridad estructural TEST↔OPS** de la infra del portal (fingerprint) y **smokes read-only end-to-end por rol** contra el gateway de OPS. La parte de alta + aviso (H.3) se cierra **por referencia** a la evidencia ya registrada de la reserva #11.

**Estado:** ✅ **Bloque H cerrado en verde.** Fingerprint TEST↔OPS **idéntico** (huella total `dee953e867aed06a9c65836bac14e8f7`); smokes **14/14 críticos en verde**, anti-OPS respetado (cero escrituras, cero consumo de secuencias); H.3 referenciada sin nueva escritura. **No se tocaron satélites ni se acuñaron IDs `D-PROMO-C-XX` / `L-PROMO-C-XX`**: eso queda para el cierre final, después del Bloque I.

---

## 1. Mapa de la promoción

| Bloque | Qué es | Estado |
|---|---|---|
| A | Snapshot baseline read-only de OPS | ✅ hecho |
| B | Infra del portal por DDL (sin seed) | ✅ hecho |
| C | Usuarios Auth OPS + seed `portal_usuarios` | ✅ hecho |
| D | Gateway `portal-api` a OPS | ✅ hecho |
| E | Los 13 wrappers n8n a OPS | ✅ cerrado |
| F | Aviso 8C-bis en el A07 de OPS | ✅ validado (alta real #11, `entorno=ops`) |
| G | Frontend OPS (build + deploy Vercel) | ✅ desplegado (commit `3a7b82d`) |
| **H** | **Smokes read-only end-to-end + fingerprint estructural** | **✅ cerrado (esta bitácora)** |
| I | Bump canónico v1.9.0 | ⏳ pendiente |
| Cierre | Bloque de cierre + propagación a satélites (`D-PROMO-C-XX`) | ⏳ pendiente (al final) |

---

## 2. H.1 — Fingerprint estructural TEST↔OPS

Se corrió el **mismo** script simétrico (`PROMO_C_BLOQUE_H_FINGERPRINT.sql`, read-only, nada seleccionado) en TEST y en OPS, y se compararon las salidas. Resultado: **huellas idénticas por objeto y en el total**.

| Objeto | Huella (TEST = OPS) |
|---|---|
| `func:public.portal_cargar_gasto_interno(jsonb)` | `82136c79acc451344e53f88f0b972bc7` |
| `tabla:portal_idempotencia` | `3143abbae64521b2600a9c8e118f8091` |
| `tabla:portal_usuarios` | `bb12480a2b316155c94302697ae1ea88` |
| **`TOTAL_PORTAL (3 objetos)`** | **`dee953e867aed06a9c65836bac14e8f7`** |

`TOTAL_PORTAL` coincide → **paridad estructural exacta** del portal entre TEST y OPS.

La huella cubre, por los 3 objetos: columnas (nombre+tipo+nullability), constraints, índices, triggers no internos, ACL, estado RLS y policies, comentarios de tabla y de cada columna, y para la función el cuerpo completo + ACL + comentario. **No entra al hash** ninguna fila, secreto, uuid, valor de secuencia, marcador de ambiente, fecha/hora ni ref del proyecto.

Robustez del fingerprint (v2 auditada): la función se resuelve por **firma exacta** (`to_regprocedure('public.portal_cargar_gasto_interno(jsonb)')`, con manejo de `<<AUSENTE>>` si no existe), no por nombre; los **ACL** (tabla y función) se serializan con los `aclitem` **ordenados por texto**; y se **normaliza `\r`** del blob completo de cada objeto antes del `md5`. Así, ni un overload, ni un orden distinto de array de grants, ni una diferencia de EOL pueden producir un falso rojo.

---

## 3. H.2 — Smokes read-only end-to-end OPS

Ejecución de `PROMO_C_BLOQUE_H_SMOKES_READONLY_OPS.ps1` contra OPS. Recorre la cadena completa (gateway → allowlist → firma HMAC → wrapper n8n → motor OPS).

- **Guard de entorno OPS:** ✅ OK (URLs con ref `lpiatqztudxiwdlcoasv` + gateway `/functions/v1/portal-api`; si no, hubiera frenado antes de pedir credenciales).
- **Login real:** ✅ OK para jenny / vicky / socio (JWT por Supabase Auth; nunca impreso).
- **B1 — `sesion.contexto` (menú por rol):** ✅ **VERDE** para los 3 roles.
  - **jenny:** 2 acciones exactas (`{sesion.contexto, calendario.limpieza}`).
  - **vicky / socio:** 14 acciones, **faltantes=0, extra=0** (allowlist estricta satisfecha: las 13 productivas presentes y nada fuera del universo `{13 productivas + W10}`).
  - **W10 (`cobranza.registrar_saldo`):** aparece solo como **INFO legado/deprecated**, no productivo y nunca invocado.
- **B2 — una lectura por acción:** ✅ **8/8 VERDE** (los 8 wrappers de lectura). **A05 (`reserva.detalle`) corrió en cobertura plena** con `id_reserva=8` (forma validada sin imprimir PII).
- **B3 — allowlist:** ✅ **3/3 VERDE**. Jenny **rebota** en las económicas con `error.code = rol_no_permitido` (HTTP 200, no 403).
- **Veredicto final:** chequeos críticos **14**, verdes **14**, parciales **0**, FRENAR **0** → **`RESULTADO: VERDE`**. **Anti-OPS respetado:** cero escrituras, cero consumo de secuencias del negocio.

---

## 4. H.3 — Alta controlada + aviso 8C-bis (por referencia)

Se mantiene por **referencia** a la evidencia ya documentada en `PROMO_C_BLOQUE_E_CIERRE.md` §4: el **alta real #11** (A07) se creó end-to-end en OPS y **disparó el aviso 8C-bis** por rama lateral no bloqueante (Call a `vita_w8cbis_alerta__OPS`, id `fHzMFj7pGMKuYEOb`), con `entorno` autoresuelto desde `leer_ambiente.valor` → **`entorno=ops`**; el sub-workflow es solo-lectura (manda mail, no escribe DB).

**No se hizo nueva escritura ni teardown nuevo** en este bloque. El teardown de la reserva #11 ya había sido ejecutado.

---

## 5. Decisiones provisionales (a formalizar como `D-PROMO-C-XX` en el cierre final)

- **Paridad estructural del portal certificada por fingerprint simétrico.** TEST↔OPS son idénticos en estructura/grants/RLS/funciones/comentarios para `portal_usuarios`, `portal_idempotencia` y `portal_cargar_gasto_interno(jsonb)` (huella total `dee953e867aed06a9c65836bac14e8f7`). El método es read-only y simétrico, sin ambiente/ref/fecha en el hash.
- **Fingerprint por firma exacta + ACL ordenado.** Las funciones se resuelven por `regprocedure` (firma exacta, no por nombre) y los `aclitem` se ordenan por texto antes de hashear; robusto a overloads y a orden de array de grants.
- **Guard de entorno OPS antes de autenticar.** Todo smoke que apunte a OPS verifica ref del proyecto + path del gateway antes de pedir credenciales o hacer login; si no cumple, frena (exit 3). Evita generar evidencia inválida contra TEST u otro entorno.
- **Verificación de menú por allowlist estricta.** El menú por rol se valida por conjunto exacto: presencia de las acciones productivas **y** ausencia de extras inesperadas, no solo presencia. W10 se admite únicamente como catálogo técnico legado informativo, nunca como acción productiva.

## 6. Lecciones provisionales (a formalizar como `L-PROMO-C-XX`)

- **El EOL real del repo es LF, no CRLF.** El repo no tiene `.gitattributes` y los 42/42 `.ps1` están en `i/lf`; la regla mnemónica "PowerShell → ASCII puro CRLF" no coincide con el remoto. Verificar siempre con `git ls-files --eol` antes de fijar EOL: la evidencia del repo gana a la regla genérica. (Confirmado: los artefactos del Bloque H van en LF.)
- **Para certificar paridad entre entornos, fingerprint simétrico + doble corrida.** Correr el mismo script en ambos lados y comparar la huella total es más simple y robusto que un diff estructural manual; normalizar `\r` y ordenar los arrays sensibles (ACL) elimina falsos rojos por EOL u orden.
- **Guard de entorno barato antes de cualquier login en scripts que tocan OPS.** Cuesta tres comparaciones de string y blinda contra el peor caso (autenticar o generar evidencia contra el entorno equivocado).

---

## 7. Pendientes y handoff

- **Bloque I** — bump canónico `6B_SCHEMA_SQL.md` → **v1.9.0** (las 3 estructuras del portal; **estructura, nunca** seeds/secretos/URLs) + regeneración del bootstrap kit pineado a la nueva versión.
- **Cierre final + satélites** — formalizar **`D-PROMO-C-XX`** / **`L-PROMO-C-XX`** (incluidos los candidatos provisionales de §5 y §6); propagar a los 6 satélites (ESTADO_ACTUAL en CRLF; resto en LF); saldar en el ledger las deudas pendientes (`D-C-64…70` de A10-MP y `D-C-71…73` del aviso A07).
- **W10** — sigue como catálogo legado/deprecated a propósito; **no** es deuda.

> **Explícito (por pedido):** en el Bloque H **no se tocó ningún satélite** (`DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `CLAUDE.md`, `Pendiente_pre_produccion.md`, `README.md`) **y no se acuñó ningún ID `D-PROMO-C-XX` / `L-PROMO-C-XX`**. Las decisiones y lecciones de §5/§6 quedan **provisionales** hasta el cierre final, que ocurre **después del Bloque I**.

---

## 8. Artefactos del bloque

- `PROMO_C_BLOQUE_H_FINGERPRINT.sql` — fingerprint estructural simétrico TEST↔OPS (H.1).
- `PROMO_C_BLOQUE_H_SMOKES_READONLY_OPS.ps1` — smokes read-only end-to-end por rol contra OPS (H.2).
- `PROMO_C_BLOQUE_H_RUNSHEET_OPS.md` — runsheet de ejecución y comparación TEST↔OPS.
- `PROMO_C_BLOQUE_H_CIERRE.md` — este cierre, con la evidencia de ejecución (huellas + veredicto) embebida.
