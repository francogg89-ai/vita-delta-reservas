# RUNSHEET — Slice 1 / Bloque 8 (wrapper de A06 `prereservas.activas`)

Carril C / Portal Operativo Interno. **Entorno: TEST únicamente.** No toca OPS ni el schema canónico.
Este bloque construye y smoke-ea el wrapper n8n **directo** (sin gateway). El cableado en `portal-api`
(CATALOG + smoke vía gateway) es el bloque siguiente.

Artefactos del bloque:
- `portal-a06-prereservas__TEMPLATE.json` — workflow n8n (sanitizado: secreto y credencial con placeholder, `active:false`).
- `C_SLICE1_B8_smoke_a06_directo.ps1` — smoke directo (8 casos).

---

## 0) Decisiones que este bloque materializa (registrar al CIERRE del slice, no ahora)
- **D-C-45** — action congelada `prereservas.activas`. El key del CATALOG y `EXPECTED_ACTION` del wrapper deben coincidir exacto.
- **D-C-46** — A06 lee `vista_prereservas_activas` como **reuse** (no query propia sobre `pre_reservas`). La vista ya encapsula la semántica de prereservas vigentes (pendiente_pago / pago_en_revision, no vencidas).
- **D-C-47** — semántica de listas: cero filas → `data:{filas:[]}` con `ok:true`, **nunca** `no_encontrado`. (Aplica también a A12.)
- Contrato **mínimo** `data:{filas}` (sin `generado_en` por ahora — evolución futura explícita si el frontend lo pide). Montos numéricos crudos; `minutos_para_vencer` redondeado; `huesped` anidado (nombre/teléfono; sin dni ni notas internas).

---

## 1) Importar el wrapper en n8n (TEST)
1. n8n Cloud → **Import from File** → `portal-a06-prereservas__TEMPLATE.json`.
2. Verificá que el Webhook quedó con **path** `portal-a06-prereservas` y **Raw Body = ON** (L-C-05; ya viene seteado).

## 2) Credencial Postgres TEST (2 nodos)
Asigná la credencial **vita_supabase_test** (placeholder `REEMPLAZAR_POR_CRED_TEST`) en:
- `leer_ambiente`
- `PG: leer prereservas`

> Ambos llevan `onError: continueRegularOutput` + `alwaysOutputData`. `PG: leer prereservas` además `executeOnce`. **A06 no tiene `queryReplacement`** (la lectura es un SELECT explícito de columnas desde `vista_prereservas_activas`, con `ORDER BY expira_en, id_pre_reserva`; sin parámetros).

## 3) Secreto HMAC — Modo B (n8n Cloud sin Variables)
En **`validar_firma_ts_rol`**, reemplazá `__PEGAR_SECRETO_O_USAR_VARIABLE__` por el **VITA_HMAC_SECRET real** (el mismo de A03/A04/A05 en TEST). El assert por prefijo aborta si te lo olvidás (L-C-10). No commitear el template con el secreto pegado.

## 4) Activar el workflow
Activá `portal-a06-prereservas` (toggle **Active**) para que responda en `/webhook/portal-a06-prereservas`.

---

## 5) (Informativo) ¿Cuántas prereservas activas hay en TEST?
Solo para **saber qué esperar** del happy path. **No hace falta que haya ninguna** — el smoke pasa con `filas=0` (D-C-47). **No crear fixtures.**

```sql
SELECT COUNT(*) AS prereservas_activas FROM vista_prereservas_activas;
-- y si querés verlas:
SELECT id_pre_reserva, cabana, estado, expira_en, minutos_para_vencer, monto_total, monto_sena
FROM vista_prereservas_activas
ORDER BY expira_en, id_pre_reserva;
```
Si da 0, los casos 1/2 igual deben devolver `ok:true | filas=0 | filas_presente=True`.

## 6) Completar y correr el smoke
En `C_SLICE1_B8_smoke_a06_directo.ps1`, sección CONFIG: `$Secret` = el mismo VITA_HMAC_SECRET pegado en el nodo. (No necesita IDs.) Corré:
```powershell
cd <carpeta>
powershell -ExecutionPolicy Bypass -File .\C_SLICE1_B8_smoke_a06_directo.ps1
```

---

## 7) Criterio de aceptación (8/8)

| # | Caso | Esperado |
|---|------|----------|
| 1 | vicky | `ok:true`, `filas_presente=True` (filas ≥ 0; **0 es válido**) |
| 2 | socio | `ok:true`, `filas_presente=True` (filas ≥ 0) |
| 3 | jenny | `ok:false`, `rol_no_permitido` |
| 4 | intruso | `ok:false`, `rol_no_permitido` |
| 5 | firma inválida | `ok:false`, `firma_invalida` |
| 6 | ts viejo (-10min) | `ok:false`, `ts_fuera_de_ventana` |
| 7 | ambiente cruzado (ops→test) | `ok:false`, `ambiente_incorrecto` (detail esperado=ops real=test) |
| 8 | action ajena (`calendario.operativo`) | `ok:false`, `accion_desconocida` |

Si hay ≥1 prereserva activa, en los casos 1/2 podés además mirar (manualmente, en la respuesta) que cada fila trae `monto_total`/`monto_sena` numéricos, `minutos_para_vencer` entero, y `huesped:{nombre,telefono}` (sin dni ni notas internas).

---

## 8) Próximo bloque (no ahora)
Con los 8/8 verdes: **cablear A06 en el gateway** (`portal-api`) — una línea en el CATALOG
```
'prereservas.activas': { handler: 'n8n', roles: ['vicky', 'socio'], webhook: 'portal-a06-prereservas', validate: payloadVacio },
```
\+ deploy por Dashboard (verify_jwt OFF, L-C-06) + **smoke vía gateway**: `sesion.contexto` incluye `prereservas.activas` para vicky/socio y no para jenny; vicky/socio → `ok:true` con `data.filas` array; jenny → `rol_no_permitido` (rebota en el gateway); sin JWT → `no_autorizado`.
