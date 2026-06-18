# Runsheet — Carril C / Slice 0 / Fase C: validación n8n + probe de ambiente (TEST)

**Entorno:** n8n Cloud TEST + Supabase TEST. **OPS no se toca.** El cruce de ambiente se prueba **dentro de** TEST.
**Objetivo:** dejar andando el patrón de revalidación en n8n (HMAC sobre raw body + ventana de ts + ambiente) y cerrar empíricamente la fidelidad del raw body (salvedad de D-C-29).
**Artefactos:** `portal-probe-ambiente__TEMPLATE.json` (workflow), `C_SLICE0_C_probe.ps1` (probe).

> Nada de esto se ejecutó. Revisá los dos artefactos antes de importar/activar/correr.

---

## Pipeline del workflow (qué hace)
`Webhook (Raw Body ON)` → `validar_firma_ts` (Code: recomputa HMAC-SHA256 sobre los bytes crudos, compara timing-safe, valida `ts` ±300s) → `leer_ambiente` (Postgres: `SELECT valor FROM configuracion_general WHERE clave='ambiente'`) → `verificar_ambiente_responder` (Code: compara `ambiente_esperado` vs real, arma envelope D-C-18) → `responder` (HTTP 200 + envelope, D-C-35).

---

## Paso 1 — Importar el workflow
1. n8n (TEST) → **Workflows** → **Import from File** → elegí `portal-probe-ambiente__TEMPLATE.json`.
2. Se crea el workflow **inactivo** llamado `portal-probe-ambiente`. No lo actives todavía.

## Paso 2 — Mapear la credencial Postgres
1. Abrí el nodo **`leer_ambiente`**. Va a mostrar la credencial como "no encontrada" (es un placeholder sanitizado).
2. En el desplegable de credencial, elegí **la credencial Postgres de TEST que ya usás en Carril B**. No crees una nueva.
3. Guardá el nodo.

## Paso 3 — Secreto HMAC (prioridad Variables, fallback in-node)
El secreto tiene que ser el **mismo valor** que pusiste en `VITA_HMAC_SECRET` de Supabase.

- **Opción A (preferida) — Variables.** Si tu plan de n8n tiene Variables: Settings → **Variables** → nueva variable `VITA_HMAC_SECRET` = (el secreto). El Code node ya la lee por `$vars.VITA_HMAC_SECRET`; no tocás el código.
- **Opción B (fallback) — in-node.** Si **no** tenés Variables: abrí `validar_firma_ts` y reemplazá el placeholder `__PEGAR_SECRETO_O_USAR_VARIABLE__` por el secreto real. **Importante:** antes de exportar/commitear el workflow, volvé a dejar el placeholder (sanitizado).

> ¿No sabés si tenés Variables? Mirá en Settings; si no aparece "Variables", andá con Opción B.

## Paso 4 — Activar y tomar la URL
1. Activá el workflow (toggle **Active**).
2. La URL de producción del webhook es:
   `https://federicosecchi.app.n8n.cloud/webhook/portal-probe-ambiente`
   (Confirmala abriendo el nodo Webhook → "Production URL". Si tu instancia usa otro host, copiá el que muestre.)

## Paso 5 — Configurar y correr el probe
1. Abrí `C_SLICE0_C_probe.ps1` y editá **dos líneas** de CONFIG:
   - `$WebhookUrl` = la URL del paso 4 (si difiere de la que ya trae).
   - `$Secret` = el mismo secreto (el real; **no** lo commitees, borralo antes de guardar al repo).
2. En PowerShell, desde la carpeta del script:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\C_SLICE0_C_probe.ps1
   ```
   (O abrí PowerShell, `cd` a la carpeta, y `.\C_SLICE0_C_probe.ps1`. Si se queja por ExecutionPolicy, usá la línea de arriba.)

El script corre los 4 casos e imprime el HTTP + el cuerpo de cada uno.

---

## Criterios de éxito / fallo

| Caso | Qué manda | Esperado (PASS) | Qué prueba |
|------|-----------|-----------------|------------|
| **1** | firma válida, `ambiente_esperado="test"` | `HTTP 200` · `{"ok":true,"data":{"ambiente":"test","rol":"vicky"}}` | **Fidelidad del raw body (D-C-29)** + ventana ts + ambiente coincide |
| **2** | firma con secreto equivocado | `{"ok":false,"error":{"code":"firma_invalida",...}}` | HMAC rechaza sobres no firmados con el secreto real |
| **3** | `ts` 10 min viejo | `{"ok":false,"error":{"code":"ts_fuera_de_ventana",...}}` | Anti-replay liviano (ventana 300s) |
| **4** | `ambiente_esperado="ops"` contra workflow TEST | `{"ok":false,"error":{"code":"ambiente_incorrecto","detail":{"esperado":"ops","real":"test"}}}` | **Muro TEST≠OPS**: un sobre para OPS no corre en TEST (sin tocar OPS) |

**Cierre de Fase C = los 4 casos PASS.** El más importante es el **1**: si da `ok:true`, el HMAC que arma el código (igual que `portal-api`) validó byte a byte en n8n → **la salvedad de D-C-29 queda cerrada a favor de "firmar bytes literales"**, sin necesidad del fallback de JSON canónico.

### Lectura de fallos
- **Caso 1 da `firma_invalida`** (con el secreto correcto en ambos lados): los bytes divergieron. Sospechosos: (a) secreto distinto entre script y n8n; (b) el Webhook no tiene **Raw Body ON**; (c) PowerShell re-encodeó el body. Avisame con el output y lo diagnostico; si fuera fidelidad real del raw body, ahí sí evaluamos el fallback de JSON canónico.
- **Caso 1 da `raw_body_ausente`**: falta activar **Raw Body** en el nodo Webhook (Paso 1, ya viene ON en el template; revisá que no se haya perdido).
- **Caso 4 da `ok:true`**: el chequeo de ambiente no está comparando bien — pegame el output.
- **Cualquier `error_interno` / 500**: probablemente la credencial Postgres (Paso 2) o el secreto sin setear (Paso 3).

---

## Sanitización antes del repo
- El workflow va al repo como **`__TEMPLATE` sanitizado**: el secreto debe quedar como `__PEGAR_SECRETO_O_USAR_VARIABLE__` (si usaste Opción B, revertí) y la credencial Postgres como placeholder. El export ya nace así si usaste Variables (Opción A).
- En `C_SLICE0_C_probe.ps1`: borrá el valor de `$Secret` antes de commitear.
- Nunca al repo: el secreto HMAC, credenciales, connection strings.

---

## Al terminar
Pegame los 4 outputs. Con eso **Slice 0 queda cerrado** (espina de seguridad completa: identidad → gateway → HMAC → ambiente, con n8n revalidando). Ahí sí toca el **cierre formal**: registrar D-C-29…D-C-35 en `DECISIONES_NO_REABRIR.md`, lecciones nuevas en `Lecciones_Aprendidas.md`, y el documento de cierre de Slice 0 + deltas a satélites — todo junto, recién al cierre.
