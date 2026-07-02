# Runsheet — A27 cuenta_corriente.al_dia (backend del wrapper, TEST)

Frente Cuenta corriente de socios / L1. Expone `cuenta_corriente_viva` en el portal como
lectura **socio-only**. Todo en **TEST**. No toca OPS, no escribe, no consume secuencias.

Orden de ejecución. Parás y me avisás en el paso 5 (smoke) antes de seguir con el gateway si
querés que verifique primero, o hacés 1→6 de corrido y me pasás el resumen del smoke.

---

## 1. Importar el workflow

En n8n (TEST): **Import from File** → `portal-a27-cuenta-corriente__TEMPLATE.json`.
Queda un workflow nuevo, inactivo, con el webhook `portal-a27-cuenta-corriente`.

## 2. Pegar el secreto HMAC (Modo B)

Abrí el nodo **`validar_firma_ts_rol`** y reemplazá el placeholder
`__PEGAR_SECRETO_O_USAR_VARIABLE__` por el secreto HMAC real (el **mismo** que usan A12/A24/A25/A26).
El template se commitea sanitizado; el secreto vive solo en el nodo de la instancia.

## 3. Elegir la credencial de Postgres (TEST)

En los **dos** nodos Postgres — `leer_ambiente` y `PG: leer cuenta corriente` — seleccioná la
credencial de Supabase **TEST** (reemplaza `REEMPLAZAR_POR_CRED_TEST`).

## 4. Activar el workflow

Activalo (toggle **Active**). El webhook queda escuchando en
`.../webhook/portal-a27-cuenta-corriente`.

## 5. Smoke directo (valida el workflow, sin gateway)

Editá `CC_L1_A27_smoke_directo.ps1`: poné el secreto en `$Secret` (mismo del paso 2). Corré:

```
powershell -ExecutionPolicy Bypass -File CC_L1_A27_smoke_directo.ps1
```

Esperado — **todo PASS**:
- **1. socio OK** → `ok:true`, con `data.filas` (imprime los saldos por socio).
- **2. vicky → rol_no_permitido** ← clave: confirma que es socio-only (vicky rebota).
- 3. jenny → rol_no_permitido · 4. intruso → rol_no_permitido.
- 5. firma equivocada → firma_invalida · 6. ts viejo → ts_fuera_de_ventana.
- 7. ambiente cruzado → ambiente_incorrecto · 8. accion equivocada → accion_desconocida.
- **F1** columnas presentes · **F2** `saldo_al_dia` = suma de las 4 columnas (por fila).
- META allowlist.

Los saldos que imprime deberían coincidir con tu corrida directa del directo (Franco/Rodrigo/Remo).

## 6. Deploy del gateway

`portal-api_A27_TEST_index.ts` es la **copia completa** del gateway A26 TEST **+ una sola entrada
aditiva** en el CATALOG (`cuenta_corriente.al_dia`, línea 734). Nada existente cambia.
Reemplazá el `index.ts` de la Edge Function `portal-api` por este archivo y deployá:

```
supabase functions deploy portal-api
```

Con esto A02 ya lista `cuenta_corriente.al_dia` en las acciones del rol **socio** (deriva del
CATALOG), y el gateway rutea al webhook del paso 1.

---

Cuando corras (al menos el smoke del paso 5) y me pases el resumen, verifico. Si está verde,
el siguiente bloque es el **frontend** (grupo nuevo "Socios" + pantalla). El smoke vía gateway
(con auth) lo puedo sumar en ese bloque o antes, como prefieras.
