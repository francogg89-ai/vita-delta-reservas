# Runsheet — A28 cuenta_corriente.detalle (wrapper L2 drill-down, TEST)

Frente Cuenta corriente de socios / L2. Expone `cuenta_corriente_detalle` (jsonb con
cascada + matriz + incidencias por gasto) como lectura **socio-only**, para el mes elegido.
Todo en **TEST**. No toca OPS, no escribe, no consume secuencias.

Base: el gateway commiteado es **A27** (`portal-api_A27_TEST_index.ts`); el delta A28 se apoya
en ese. Igual que en A27, parás en el paso 5 (smoke) y me avisás, o hacés 1→6 de corrido.

---

## 1. Importar el workflow

n8n (TEST): **Import from File** → `portal-a28-cuenta-corriente-detalle__TEMPLATE.json`.
Workflow nuevo, inactivo, webhook `portal-a28-cuenta-corriente-detalle`.

## 2. Pegar el secreto HMAC

Nodo **`validar_firma_ts_rol`**: reemplazá `__PEGAR_SECRETO_O_USAR_VARIABLE__` por el secreto
HMAC real (el **mismo** de A12/A24/A25/A26/A27).

## 3. Credencial de Postgres (TEST)

En los **dos** nodos Postgres — `leer_ambiente` y `PG: leer detalle` — elegí la credencial de
Supabase **TEST**.

## 4. Activar

Activá el workflow (**Active**).

## 5. Smoke directo (valida el workflow, sin gateway)

Editá `CC_L2_A28_smoke_directo.ps1`: poné el secreto en `$Secret`. Corré:

```
powershell -ExecutionPolicy Bypass -File CC_L2_A28_smoke_directo.ps1
```

Esperado — **todo PASS**:
- Seguridad: **1. socio OK** · **2. vicky → rol_no_permitido** (socio-only) · 3. jenny → rol_no_permitido · 4. firma → firma_invalida · 5. ts viejo → ts_fuera_de_ventana · 6. ambiente → ambiente_incorrecto · 7. accion → accion_desconocida.
- Payload `{mes}`: **8. sin mes → payload_invalido** · **9. mes mal formado → payload_invalido** · **10. mes pre-piso (2026-05) → payload_invalido** · **11. clave extra → payload_invalido**.
- Funcional: **F1** `data.mes` == mes pedido (prueba que el wrapper pasó el mes bien) · **F2** el jsonb trae las 6 claves · **F3** cascada no vacía. Imprime los tamaños de cada sección.

## 6. Deploy del gateway

`portal-api_A28_TEST_index.ts` = copia del gateway **A27** + dos cosas aditivas: el validador
`payloadCuentaCorrienteDetalle` (valida `{mes}`) y la entrada `cuenta_corriente.detalle` en el
CATALOG. Nada existente cambia. Reemplazá el `index.ts` de `portal-api` por este y deployá:

```
supabase functions deploy portal-api
```

A02 lista `cuenta_corriente.detalle` para el rol **socio** automáticamente (deriva del CATALOG).

---

Cuando corras (al menos el smoke) y me pases el resumen, verifico. Si está verde, el bloque que
cierra L2 es el **frontend**: la pantalla de drill-down (selector de mes + las tres secciones) en
el grupo "Socios".
