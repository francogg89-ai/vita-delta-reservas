# OPS-A — Runsheet: wrapper A26 en n8n OPS (`portal-a26-disponibilidad__OPS`)

**Etapa:** Promoción A26 a OPS — Bloque **OPS-A** (contingencia: la grilla de A07/A08 está rota en OPS porque A26 falta en el gateway). Este bloque deja el **wrapper A26 vivo en n8n OPS** y lo valida con smoke directo. **NO** toca gateway, frontend, SQL, canónico ni Vercel.
**Quién ejecuta:** Franco (importa en n8n, repunta credencial, pega HMAC OPS, activa, corre smoke). Claude generó y validó; **no toca OPS**.
**Read-only / anti-OPS:** A26 es lectura pura → cero escrituras, cero secuencias, cero reservas/bloqueos. No se crea ni modifica nada.

---

## 0. Artefactos de OPS-A

| Archivo | Qué es |
|---|---|
| `portal-a26-disponibilidad__OPS.json` | Workflow n8n a importar en OPS. |
| `A26_smoke_oracle_OPS.sql` | Oráculo read-only para elegir cabaña/ventana reales de OPS (bloques [A]–[E], editar literales `<<<`). |
| `A26_smoke_directo_OPS.ps1` | Smoke directo HMAC read-only contra el webhook OPS (guard anti-OPS exit 3). |

## 1. Pre-flight (vos, antes de importar)

- **R1 confirmado:** OPS auto-desplegó Bloque C y la grilla está rota. Esta es la ruta urgente para des-romperla (OPS-A → OPS-B). La excepción D-FE-23 queda viva hasta OPS-H.
- **HMAC OPS disponible:** el mismo `VITA_HMAC_SECRET` de OPS que usan los otros 13 wrappers `__OPS` y el gateway OPS. Lo necesitás en dos lugares: (a) en el nodo `validar_firma_ts_rol` del wrapper; (b) en `$env:VITA_OPS_A26_HMAC` para el smoke. **Mismo valor en ambos.**
- **Base n8n OPS:** confirmá si los `__OPS` cuelgan de `/webhook` (producción, workflow activo) o `/webhook-test` (editor con "Listen").
- **`obtener_disponibilidad_rango` existe en OPS:** es canónica (bootstrap v1.9.0). Verificación rápida read-only opcional: `SELECT proname FROM pg_proc WHERE proname='obtener_disponibilidad_rango';`.

## 2. Importar el wrapper en n8n OPS

1. **Importar** `portal-a26-disponibilidad__OPS.json` (Workflows → Import from File).
2. **Repuntar credencial Postgres en los DOS nodos** (`leer_ambiente` y `PG: disponibilidad`): seleccioná la **credencial de OPS** (en el JSON viene como placeholder `vita_supabase_ops (reemplazar al importar)`). Ambos nodos deben quedar con la credencial OPS.
3. **Pegar el HMAC OPS** en el nodo `validar_firma_ts_rol`: reemplazá el placeholder `__PEGAR_SECRETO_O_USAR_VARIABLE__` por el secreto HMAC real de OPS (Modo B). *(El nodo asserta por prefijo `__PEGAR_`: si te olvidás, tira error claro.)*
4. **Confirmar:** path del Webhook = `portal-a26-disponibilidad__OPS`; opción **Raw Body = ON** (ya viene `rawBody:true` en el JSON; el HMAC depende de los bytes crudos); `responseMode = responseNode`.
5. **Activar** el workflow (o dejarlo en editor con "Listen" si vas a probar por `/webhook-test`).

> El wrapper **no** discrimina ambiente por valor hardcodeado: `verificar_acceso` compara `ambiente_esperado` (del sobre) contra `leer_ambiente` (la DB). Con la credencial OPS, `leer_ambiente` devuelve `ops` solo: por eso el sobre del smoke manda `ambiente_esperado='ops'`.

## 3. Oráculo (elegir cabaña/ventana reales de OPS)

Correr `A26_smoke_oracle_OPS.sql` contra **OPS** (read-only). En el SQL Editor de Supabase corré cada bloque seleccionándolo (L-8A-01):
- **[A]** elegí una cabaña con `activa=true` para `$CabValida` (cabañas 1-5) y confirmá que `999999` no figure activa.
- **[C]/[D]** si hay ocupación real próxima, elegí una ventana `[OcupDesde, OcupHasta)` con algo ocupado/bloqueado y, si aparece, una fila `checkout_disponible` para `$FechaCheckout`. **Si OPS no tiene ocupación próxima, dejá esos campos vacíos**: T5/T6 quedan SKIP y el contrato igual se cubre con T1-T4 y T7-T13.

## 4. Smoke directo (read-only)

1. **Definí el secreto por entorno** (no se hardcodea, no se imprime):
   `$env:VITA_OPS_A26_HMAC = '<secreto HMAC OPS>'`
2. (Si hace falta) ajustá en el `.ps1`: `$BaseUrl`, `$WebhookSeg` (`webhook` vs `webhook-test`), `$CabValida`, y `$OcupDesde/$OcupHasta/$FechaCheckout` desde el oráculo.
3. Corré: `powershell -ExecutionPolicy Bypass -File .\A26_smoke_directo_OPS.ps1`

**Guard anti-OPS:** el smoke FRENA (exit 3) si `$Webhook` no termina en `__OPS` o si `$Ambiente != 'ops'`. Falta el secreto → exit 2. Algún caso en rojo → exit 1.

**Casos (mínimos pedidos):**
| Caso | Espera |
|---|---|
| T1 cabaña activa sin ocupación | `ok:true`, `dias` no vacío, todos `disponible` |
| T2 cabaña inexistente (999999) | `no_encontrado` |
| T3 rango invertido | `payload_invalido` |
| T4 span > 366 | `payload_invalido` |
| T5/T6 ventana con ocupación / checkout | estructura OK / `checkout_disponible` (SKIP si no llenaste el oráculo) |
| T7 firma adulterada | `firma_invalida` |
| **T8 rol jenny** | **`rol_no_permitido`** |
| T9 action equivocada | `accion_desconocida` |
| **T10 `ambiente_esperado='test'`** (mismatch en OPS) | **`ambiente_incorrecto`** |
| T11 clave desconocida | `payload_invalido` |
| T12a/b/c `id_cabana` 0/negativo/string | `payload_invalido` |
| T13 falta `fecha_hasta` | `payload_invalido` |

**Verde esperado:** `FAIL=0`. T5/T6 pueden quedar SKIP. **Cero escrituras, cero secuencias.**

## 5. Evidencia de validación (corrida por Claude)

| Check | Resultado |
|---|---|
| `portal-a26-disponibilidad__OPS.json` parsea | OK |
| webhook path == `portal-a26-disponibilidad__OPS` | OK |
| 0 ocurrencias de `portal-a26-disponibilidad` **sin sufijo** | OK |
| 0 ocurrencias `__TEST` | OK |
| 0 candado hardcodeado `!== 'test'` (ni `'test'` suelto) | OK |
| credencial OPS placeholder ×2, 0 referencias TEST | OK |
| HMAC placeholder `__PEGAR_` preservado (Franco pega OPS) | OK |
| ambos nodos PG `executeQuery`; SQL sin `INSERT/UPDATE/DELETE/nextval/DDL` | OK |
| `node --check` (async-wrapped) en los 3 nodos code | OK |
| `pglast` parse de las 2 queries SQL | OK |
| smoke ASCII puro; llaves balanceadas (107/107) | OK |
| smoke: secreto TEST **eliminado**; usa `$env:VITA_OPS_A26_HMAC` | OK |
| smoke: `__OPS`, `ambiente=ops`, guard anti-OPS (exit 3), T10 invertido | OK |
| oráculo ASCII puro, read-only, `pglast` OK | OK |

> El único chequeo no-diagnóstico es el balance de paréntesis sobre todo el texto (delta `-8` **idéntico** en TEST y OPS por la notación `[in,out)` y comentarios; no se valida con `pwsh` por no estar disponible en el entorno).

## 6. Después de OPS-A

Apenas el smoke esté verde (FAIL=0), seguimos con **OPS-B**: agregar el validator `payloadDisponibilidadCabana` + la action `disponibilidad.cabana` (webhook `portal-a26-disponibilidad__OPS`) al gateway `portal-api` OPS y redesplegar → **eso des-rompe la grilla** de A07/A08 en OPS. Luego OPS-H (B2/B3) para cerrar la excepción D-FE-23, y el smoke visual / cierre.
