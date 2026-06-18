# RUNSHEET — Carril C / Slice 1 / Bloque 2 — Wrapper `portal-a03-limpieza` (n8n TEST)

**Objetivo:** crear y publicar el workflow n8n `portal-a03-limpieza` en TEST y validarlo con
pruebas directas. **NO se toca `portal-api` ni el CATALOG** (D-C-31): A03 se cablea recién en
el Bloque 3. Al terminar este bloque, `sesion.contexto.acciones` sigue en `["sesion.contexto"]`.

**Entorno:** TEST (`vita-delta-test`). **OPS y `6B_SCHEMA_SQL.md` intocables.**
**Artefactos:** `portal-a03-limpieza__TEMPLATE.json` (importar a n8n) · `C_SLICE1_B2_probe_a03.ps1` (pruebas).

El wrapper reusa el **render exacto** del workflow viejo `vita_w8c_html_limpieza` (la grilla
semanal que el equipo conoce), con el front de seguridad del patrón Fase C antepuesto. **No
llama el webhook viejo** (D-C-36): trae la query/lógica/render, no el endpoint.

---

## Estructura del wrapper (qué importás)

`Webhook (Raw Body)` → `validar_firma_ts_rol` (HMAC sobre binario + ts ±300s + **allowlist
`{jenny,vicky,socio}`** + **action binding** `calendario.limpieza` + assert duro de secreto) →
`leer_ambiente` → `verificar_acceso` (firma + rol + action + ambiente → envelope error, o marca
de paso) → **`IF acceso`** → si OK: los 5 reads de limpieza (`vista_limpieza_semana` +
grilla/detalle/bloqueos/salidas) → `render envelope` → `Respond`; si NO: `Respond` con el error.
Salida siempre envelope: éxito `{ok:true,data:{formato:"html",html}}`, error `{ok:false,error:{code,...}}`.
El wrapper queda blindado en **cinco dimensiones**: HMAC · ts · rol · action · ambiente.

> El `IF acceso` corta **antes** de los 5 reads: una firma/rol/ambiente inválidos no llegan a
> consultar la base (solo el `leer_ambiente` liviano corre antes, igual que el probe de Slice 0).

---

## Pasos

### 1 — Importar el template
n8n → Workflows → **Import from File** → `portal-a03-limpieza__TEMPLATE.json`. Llega como
**inactivo** (`active:false`) y con credencial/secreto en **placeholder** (por diseño).

### 2 — Asignar la credencial Postgres (6 nodos)
En cada nodo Postgres (`leer_ambiente` + los 5 `PG: leer *`) seleccioná la credencial real
**`vita_supabase_test`**. Hoy muestran el placeholder `vita_supabase_test (reemplazar al
importar)` → reemplazá por la credencial verdadera.

### 3 — Setear la Variable de n8n `VITA_HMAC_SECRET`
El nodo `validar_firma_ts_rol` lee el secreto de `$vars.VITA_HMAC_SECRET`. Seteá esa Variable
en n8n con el **mismo valor** que `VITA_HMAC_SECRET` en Supabase (el rotado 2026-06-16).
**Assert duro:** si la Variable no está, el nodo hace `throw` y **toda** llamada falla ruidosa
(es a propósito: no opera con el placeholder).

### 4 — Activar el workflow
Para que la URL de **producción** del webhook (`…/webhook/portal-a03-limpieza`) responda,
**activá** el workflow. (En TEST es seguro: aunque quede vivo, el portal todavía no puede
llegar — A03 no está en el CATALOG hasta el Bloque 3.) Alternativa sin activar: usar "Listen
for test event" + la URL `…/webhook-test/…` por cada llamada (tedioso para 6 casos).

### 5 — Correr el probe directo
En `C_SLICE1_B2_probe_a03.ps1`, pegá el `VITA_HMAC_SECRET` en `$Secret` (la URL ya está puesta).
Corré:

```
powershell -ExecutionPolicy Bypass -File .\C_SLICE1_B2_probe_a03.ps1
```

Esperado:

| # | Caso | Esperado |
|---|---|---|
| 1 | firma válida + rol **jenny** + test | `ok:true  formato=html  html_len=<grande>` |
| 2 | firma inválida | `ok:false  code=firma_invalida` |
| 3 | ts viejo (10 min) | `ok:false  code=ts_fuera_de_ventana` |
| 4 | ambiente cruzado (`ops`) | `ok:false  code=ambiente_incorrecto  detail={"esperado":"ops","real":"test"}` |
| 5 | rol permitido **vicky** + test | `ok:true  formato=html  html_len=<grande>` |
| 6 | rol **intruso** directo al wrapper | `ok:false  code=rol_no_permitido` |
| 7 | firma válida + rol jenny + **action incorrecta** | `ok:false  code=accion_desconocida` |

Caso 1 y 5 prueban rol permitido (jenny y vicky); caso 6 prueba que la allowlist del wrapper
rebota un rol fuera de lista; caso 7 prueba el **action binding** (un sobre bien firmado para
otra acción no entra a este endpoint). Aunque A03 habilite los tres roles en uso normal.

### 6 — Reconfirmar que `portal-api` no cambió
Corré de nuevo el smoke de Bloque 1A (`C_SLICE1_B1A_smoke_sesion_contexto.ps1`). Debe seguir
dando **`acciones=["sesion.contexto"]`** en los tres usuarios. Si A03 apareciera, algo se tocó
de más (condición 7: Bloque 2 no toca `portal-api`/CATALOG).

---

## Criterio de cierre de Bloque 2

- 7/7 casos del probe con su esperado (incluido `rol_no_permitido` directo, `ambiente_incorrecto`
  y `accion_desconocida` por action binding).
- Casos 1 y 5: HTML real dentro del envelope (`formato=html`, `html_len` grande).
- `sesion.contexto.acciones` sigue en `["sesion.contexto"]`.

Con eso cerrado, pasamos al **Bloque 3**: agregar A03 al CATALOG de `portal-api`
(`handler:'n8n'`, webhook `portal-a03-limpieza`, roles `{jenny,vicky,socio}`, `validate:payloadVacio`),
desplegar, y correr los smokes **vía portal-api** (Jenny→A03 OK, Vicky/Socio→A03 OK, sin
JWT→no_autorizado). **Si algo del Bloque 2 difiere del esperado, no avanzar — reportar.**
